#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>

#include "qstruct/compiler.h"

ssize_t calculate_qstruct_packing(struct qstruct_definition *def);


%%{
  machine qstruct;
  write data;
}%%

struct qstruct_definition *parse_qstructs(char *schema, size_t schema_size, char *err_buf, size_t err_buf_size) {
  char *p = schema, *pe = schema + schema_size, *eof = 0;
  int cs = -1;

  int curr_line = 1;
  ssize_t i;
  int err = 0;

  struct qstruct_definition *def = NULL, *new_def;
  struct qstruct_item curr_item;
  ssize_t curr_item_index;

  struct qstruct_item *new_items;
  ssize_t items_allocated;
  ssize_t largest_item;
  ssize_t packing_result;
  struct qstruct_item *item_hash_by_name = NULL, *item_lookup;

  char err_ctx_buf[256];
  char err_desc_buf[512];
  char *err_ctx_start, *err_ctx_end;


  // the ragel state machine will initialise these variables, assignments silence compiler warnings
  curr_item_index = 0;
  memset(&curr_item, '\0', sizeof(curr_item));
  items_allocated = 0;
  largest_item = -1;


  #define PARSE_ERROR(...) do { \
    snprintf(err_desc_buf, sizeof(err_desc_buf), __VA_ARGS__); \
    for(err_ctx_start=p; err_ctx_start>schema && *err_ctx_start != '\n' && (p-err_ctx_start) < 20; err_ctx_start--) {} \
    while (isspace(*err_ctx_start) && err_ctx_start < p) err_ctx_start++; \
    for(err_ctx_end=p; err_ctx_end<(pe-1) && *err_ctx_end != '\n' && (err_ctx_end-p) < 20; err_ctx_end++) {} \
    memcpy(err_ctx_buf, err_ctx_start, err_ctx_end - err_ctx_start); \
    *(err_ctx_buf + (err_ctx_end - err_ctx_start)) = '\0'; \
    snprintf(err_buf, err_buf_size, "\n------------------------------------------------------------\nQstruct schema parse error (line %d, character %d)\n\n  %s\n  %*s^\n  %*s|--%s\n\n------------------------------------------------------------\n", curr_line, (int)(p-schema), err_ctx_buf, (int)(p-err_ctx_start), " ", (int)(p-err_ctx_start), " ", err_desc_buf); \
    err = 1; \
    goto bail; \
  } while(0);

  %%{
    action init_qstruct {
      new_def = malloc(sizeof(struct qstruct_definition));
      if (new_def == NULL)
        PARSE_ERROR("out of memory");

      new_def->next = def;
      def = new_def;
      new_def = NULL;

      items_allocated = 64;
      def->items = malloc(items_allocated * sizeof(struct qstruct_item));
      if (def->items == NULL)
        PARSE_ERROR("out of memory");

      largest_item = -1;
      for (i=0; i<items_allocated; i++) def->items[i].occupied = 0;
    }

    action handle_item {
      if (curr_item_index < 0)
        PARSE_ERROR("id value overflow"); // FIXME: prolly need to check upper bound

      if (curr_item_index >= items_allocated) {
        new_items = realloc(def->items, curr_item_index*2 * sizeof(struct qstruct_item));
        if (new_items == NULL) 
          PARSE_ERROR("out of memory");

        def->items = new_items;
        new_items = NULL;

        for(i=items_allocated; i<curr_item_index*2; i++) def->items[i].occupied = 0;
        items_allocated = curr_item_index*2;
      }

      if ((curr_item.type & 0xFFFF) == QSTRUCT_TYPE_BOOL && (curr_item.type & (QSTRUCT_TYPE_MOD_ARRAY_FIX | QSTRUCT_TYPE_MOD_ARRAY_DYN)))
        PARSE_ERROR("bools can't be arrays");

      if ((curr_item.type & 0xFFFF) == QSTRUCT_TYPE_STRING && (curr_item.type & QSTRUCT_TYPE_MOD_ARRAY_FIX))
        PARSE_ERROR("strings can't be fixed-size arrays");

      if ((curr_item.type & 0xFFFF) == QSTRUCT_TYPE_BLOB && (curr_item.type & QSTRUCT_TYPE_MOD_ARRAY_FIX))
        PARSE_ERROR("blobs can't be fixed-size arrays");

      if (def->items[curr_item_index].occupied)
        PARSE_ERROR("duplicated index %ld", curr_item_index);

      def->items[curr_item_index].name = curr_item.name;
      def->items[curr_item_index].name_len = curr_item.name_len;
      def->items[curr_item_index].type = curr_item.type;
      def->items[curr_item_index].fixed_array_size = curr_item.fixed_array_size;
      def->items[curr_item_index].occupied = 1;

      if (curr_item_index > largest_item) largest_item = curr_item_index;
    }

    action handle_qstruct {
      for(i=0; i<=largest_item; i++) {
        if (!def->items[i].occupied)
          PARSE_ERROR("missing item %ld", i);

        HASH_FIND(hh, item_hash_by_name, def->items[i].name, def->items[i].name_len, item_lookup);
        if (item_lookup)
          PARSE_ERROR("duplicate item name '%.*s'", (int) def->items[i].name_len, def->items[i].name);

        HASH_ADD_KEYPTR(hh, item_hash_by_name, def->items[i].name, def->items[i].name_len, &def->items[i]);
      }

      HASH_CLEAR(hh, item_hash_by_name);

      def[0].num_items = largest_item+1;

      packing_result = calculate_qstruct_packing(def);
      if (packing_result < 0)
        PARSE_ERROR("memory error in packing");

      def[0].body_size = (size_t) packing_result - QSTRUCT_HEADER_SIZE;
    }


    newline = '\n' @{curr_line++;};
    any_count_line = any | newline;
    whitespace_char = any_count_line - 0x21..0x7e;

    alnum_u = alnum | '_';
    alpha_u = alpha | '_';
    identifier = alpha_u alnum_u*;
    identifier_with_package = alpha_u alnum_u* ('::' alpha_u alnum_u*)*;
    integer = digit+;

    ws = (
           whitespace_char |
           ( '#' [^\n]* newline ) |
           ( '/*' ( ( any_count_line )* - ( any_count_line* '*/' any_count_line* ) ) '*/' )
         );

    type = 'string' %{ curr_item.type = QSTRUCT_TYPE_STRING; } |
           'blob' %{ curr_item.type = QSTRUCT_TYPE_BLOB; } |
           'bool' %{ curr_item.type = QSTRUCT_TYPE_BOOL; } |
           'float' %{ curr_item.type = QSTRUCT_TYPE_FLOAT; } |
           'double' %{ curr_item.type = QSTRUCT_TYPE_DOUBLE; } |
           'int8' %{ curr_item.type = QSTRUCT_TYPE_INT8; } |
           'uint8' %{ curr_item.type = QSTRUCT_TYPE_INT8 | QSTRUCT_TYPE_MOD_UNSIGNED; } |
           'int16' %{ curr_item.type = QSTRUCT_TYPE_INT16; } |
           'uint16' %{ curr_item.type = QSTRUCT_TYPE_INT16 | QSTRUCT_TYPE_MOD_UNSIGNED; } |
           'int32' %{ curr_item.type = QSTRUCT_TYPE_INT32; } |
           'uint32' %{ curr_item.type = QSTRUCT_TYPE_INT32 | QSTRUCT_TYPE_MOD_UNSIGNED; } |
           'int64' %{ curr_item.type = QSTRUCT_TYPE_INT64; } |
           'uint64' %{ curr_item.type = QSTRUCT_TYPE_INT64 | QSTRUCT_TYPE_MOD_UNSIGNED; }
      ;

    array_spec = ('['
                    ws*
                    integer >{ curr_item.fixed_array_size = 0; }
                            @{ curr_item.fixed_array_size = curr_item.fixed_array_size * 10 + (fc - '0'); }
                    ws*
                  ']' >{ curr_item.type |= QSTRUCT_TYPE_MOD_ARRAY_FIX; }

                   |

                   '[' ws* ']' >{ curr_item.type |= QSTRUCT_TYPE_MOD_ARRAY_DYN; }
                 );

    item = identifier >{ curr_item.name = p; curr_item.fixed_array_size = 1; }
                      %{ curr_item.name_len = p - curr_item.name; }
                      $!{ PARSE_ERROR("invalid identifier"); }
           ws+
           '@' $!{ PARSE_ERROR("expected @ id"); }
           integer >{ curr_item_index = 0; }
                   @{ curr_item_index = curr_item_index * 10 + (fc - '0'); }
           ws+
           type $!{ PARSE_ERROR("unrecognized type"); }
           ws*
           array_spec?
             $!{ PARSE_ERROR("invalid array specifier"); }
           ws* ';' $!{ PARSE_ERROR("missing semi-colon"); } ;

    qstruct = ws*
              ( [qQ] 'struct' ) >init_qstruct
                                $!{ PARSE_ERROR("expected qstruct definition"); }
              ws+
              identifier_with_package >{ def[0].name = p; }
                                      %{ def[0].name_len = p - def[0].name; }
              ws*
             '{'
               ws* (item @handle_item ws*)*
             '}' @handle_qstruct
             (ws* ';')?;

    ########################

    main := qstruct* ws*;

    write init;
    write exec;
  }%%

  if (cs < qstruct_first_final)
    PARSE_ERROR("general parse error");

  bail:

  HASH_CLEAR(hh, item_hash_by_name);

  if (err) {
    free_qstruct_definitions(def);
    return NULL;
  }

  return def;
}


void free_qstruct_definitions(struct qstruct_definition *def) {
  struct qstruct_definition *temp;

  while (def) {
    if (def->items) free(def->items);
    temp = def->next;
    free(def);
    def = temp;
  }
}
