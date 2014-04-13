#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "qstruct_compiler.h"
#include "internal.h"


%%{
  machine qstruct;
  write data;
}%%

#define PARSE_ERROR(...) do { \
  snprintf(err_buf, err_buf_size, __VA_ARGS__); \
  err = 1; \
  goto bail; \
} while(0);

struct qstruct_definition *parse_qstructs(char *schema, size_t schema_size, char *err_buf, size_t err_buf_size) {
  char *p = schema, *pe = schema + schema_size;
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


  // the ragel state machine will initialise these variables, assignments silence compiler warnings
  curr_item_index = 0;
  memset(&curr_item, '\0', sizeof(curr_item));
  items_allocated = 0;
  largest_item = -1;


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
      if (curr_item_index >= items_allocated) {
        new_items = realloc(def->items, curr_item_index*2 * sizeof(struct qstruct_item));
        if (new_items == NULL) 
          PARSE_ERROR("out of memory");

        def->items = new_items;
        new_items = NULL;

        for(i=items_allocated; i<curr_item_index*2; i++) def->items[i].occupied = 0;
        items_allocated = curr_item_index*2;
      }

      if (curr_item.type == QSTRUCT_TYPE_BOOL && curr_item.fixed_array_size != 1)
        PARSE_ERROR("bools can't be arrays (line %d)", curr_line);

      if (def->items[curr_item_index].occupied)
        PARSE_ERROR("duplicated index %ld (line %d)", curr_item_index, curr_line);

      def->items[curr_item_index].name = curr_item.name;
      def->items[curr_item_index].name_len = curr_item.name_len;
      def->items[curr_item_index].type = curr_item.type;
      def->items[curr_item_index].fixed_array_size = curr_item.fixed_array_size;
      def->items[curr_item_index].occupied = 1;

      if (curr_item_index > largest_item) largest_item = curr_item_index;
    }

    action handle_qstruct {
      for(i=0; i<largest_item; i++) {
        if (!def->items[i].occupied)
          PARSE_ERROR("missing item %ld (line %d)", i, curr_line);
      }

      def[0].num_items = largest_item+1;

      packing_result = calculate_qstruct_packing(def);
      if (packing_result < 0)
        PARSE_ERROR("memory error in packing (line %d)", curr_line);

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
                    integer >{ curr_item.type |= QSTRUCT_TYPE_MOD_ARRAY_FIX; curr_item.fixed_array_size = 0; }
                            @{ curr_item.fixed_array_size = curr_item.fixed_array_size * 10 + (fc - '0'); }
                  ']'

                   |

                   '[' ws* ']' >{ curr_item.type |= QSTRUCT_TYPE_MOD_ARRAY_DYN; }
                 );

    item = identifier >{ curr_item.name = p; curr_item.fixed_array_size = 1; }
                      %{ curr_item.name_len = p - curr_item.name; }
           ws+
           '@' integer >{ curr_item_index = 0; }
                       @{ curr_item_index = curr_item_index * 10 + (fc - '0'); }
           ws+
           type array_spec?
           ws* ';';

    qstruct = ws*
              'qstruct' >init_qstruct
              ws+
              identifier_with_package >{ def[0].name = p; }
                                      %{ def[0].name_len = p - def[0].name; }
              ws*
             '{'
               ws* (item @handle_item ws*)*
             '}' @handle_qstruct;

    ########################

    main := qstruct* ws*;

    write init;
    write exec;
  }%%

  if (cs < qstruct_first_final)
    PARSE_ERROR("general parse error (line %d)", curr_line);

  bail:

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
