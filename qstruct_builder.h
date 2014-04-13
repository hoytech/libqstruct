#ifndef _QSTRUCT__QSTRUCT_BUILDER_H
#define _QSTRUCT__QSTRUCT_BUILDER_H

#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "qstruct_utils.h"


struct qstruct_builder {
  char *buf;
  size_t buf_size;
  size_t msg_size;
};

static inline struct qstruct_builder *qstruct_builder_new() {
  struct qstruct_builder *builder;

  builder = malloc(sizeof(struct qstruct_builder));
  if (builder == NULL) return NULL;

  builder->msg_size = 16;
  builder->buf_size = 4096;
  builder->buf = calloc(builder->buf_size, 1);

  if (builder->buf == NULL) {
    free(builder);
    return NULL;
  }

  return builder;
}

static inline void qstruct_builder_free(struct qstruct_builder *builder) {
  if (builder->buf) free(builder->buf);
  free(builder);
}

static inline size_t qstruct_builder_get_msg_size(struct qstruct_builder *builder) {
  return builder->msg_size;
}

static inline void qstruct_builder_update_msg_size(struct qstruct_builder *builder) {
  uint64_t msg_size;

  msg_size = (uint64_t) builder->msg_size - 16; // this field stores body size
  QSTRUCT_STORE_8BYTE_LE(&msg_size, builder->buf + 8);
}

static inline char *qstruct_builder_get_buf(struct qstruct_builder *builder) {
  qstruct_builder_update_msg_size(builder);

  return builder->buf;
}

static inline char *qstruct_builder_steal_buf(struct qstruct_builder *builder) {
  char *buf;

  qstruct_builder_update_msg_size(builder);

  buf = builder->buf;
  builder->buf = NULL;

  return buf;
}




static inline int qstruct_builder_expand_msg(struct qstruct_builder *builder, size_t new_buf_size) {
  char *new_buf;

  if (new_buf_size > builder->buf_size) {
    new_buf = realloc(builder->buf, new_buf_size);
    if (new_buf == NULL) return -1;

    memset(builder->buf + builder->buf_size, '\0', new_buf_size - builder->buf_size);
    builder->buf_size = new_buf_size;
  }

  if (new_buf_size > builder->msg_size) builder->msg_size = new_buf_size;

  return 0;
}

static inline int qstruct_builder_set_uint64(struct qstruct_builder *builder, size_t byte_offset, uint64_t value) {
  if (qstruct_builder_expand_msg(builder, byte_offset + 8)) return -1;

  QSTRUCT_STORE_8BYTE_LE(&value, builder->buf + byte_offset);

  return 0;
}

static inline int qstruct_builder_set_bool(struct qstruct_builder *builder, size_t byte_offset, int bit_offset, int value) {
  if (qstruct_builder_expand_msg(builder, byte_offset + 1)) return -1;

  if (value) {
    *((uint8_t *)(builder->buf + byte_offset)) |= bit_offset;
  } else {
    *((uint8_t *)(builder->buf + byte_offset)) &= ~bit_offset;
  }

  return 0;
}

static inline int qstruct_builder_set_string(struct qstruct_builder *builder, size_t byte_offset, char *value, size_t value_size) {
  if (qstruct_builder_expand_msg(builder, byte_offset + 16)) return -1;

  if (value_size < 16) {
    *((uint8_t *)(builder->buf + byte_offset)) = (uint8_t) value_size;
    memcpy(builder->buf + byte_offset + 1, value, value_size);
  } else {
    assert(0); // not impl
  }

  return 0;
}

#endif
