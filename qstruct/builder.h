#ifndef _QSTRUCT__QSTRUCT_BUILDER_H
#define _QSTRUCT__QSTRUCT_BUILDER_H

#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#include "qstruct/utils.h"


struct qstruct_builder {
  char *buf;
  size_t buf_size;
  size_t msg_size;
};

static inline struct qstruct_builder *qstruct_builder_new(size_t body_size) {
  struct qstruct_builder *builder;
  uint64_t body_size64;

  builder = malloc(sizeof(struct qstruct_builder));
  if (builder == NULL) return NULL;

  builder->msg_size = 16 + body_size;
  builder->buf_size = builder->msg_size + 4096;

  builder->buf = calloc(builder->buf_size, 1);

  if (builder->buf == NULL) {
    free(builder);
    return NULL;
  }

  body_size64 = (uint64_t) body_size;
  QSTRUCT_STORE_8BYTE_LE(&body_size64, builder->buf + 8);

  return builder;
}

static inline void qstruct_builder_free(struct qstruct_builder *builder) {
  if (builder->buf) free(builder->buf);
  free(builder);
}

static inline size_t qstruct_builder_get_msg_size(struct qstruct_builder *builder) {
  return builder->msg_size;
}

static inline char *qstruct_builder_get_buf(struct qstruct_builder *builder) {
  return builder->buf;
}

static inline char *qstruct_builder_steal_buf(struct qstruct_builder *builder) {
  char *buf;

  buf = builder->buf;
  builder->buf = NULL;

  return buf;
}

static inline int qstruct_builder_expand_msg(struct qstruct_builder *builder, size_t new_buf_size) {
  char *new_buf;

  if (new_buf_size > builder->buf_size) {
    new_buf = realloc(builder->buf, new_buf_size);
    if (new_buf == NULL) return -1;

    builder->buf = new_buf;
    new_buf = NULL;

    memset(builder->buf + builder->buf_size, '\0', new_buf_size - builder->buf_size);
    builder->buf_size = new_buf_size;
  }

  if (new_buf_size > builder->msg_size) builder->msg_size = new_buf_size;

  return 0;
}



static inline int qstruct_builder_set_uint64(struct qstruct_builder *builder, size_t byte_offset, uint64_t value) {
  if (byte_offset + 8 > builder->msg_size) return -1;

  QSTRUCT_STORE_8BYTE_LE(&value, builder->buf + byte_offset);

  return 0;
}

static inline int qstruct_builder_set_uint32(struct qstruct_builder *builder, size_t byte_offset, uint32_t value) {
  if (byte_offset + 4 > builder->msg_size) return -1;

  QSTRUCT_STORE_4BYTE_LE(&value, builder->buf + byte_offset);

  return 0;
}

static inline int qstruct_builder_set_uint16(struct qstruct_builder *builder, size_t byte_offset, uint16_t value) {
  if (byte_offset + 2 > builder->msg_size) return -1;

  QSTRUCT_STORE_2BYTE_LE(&value, builder->buf + byte_offset);

  return 0;
}

static inline int qstruct_builder_set_uint8(struct qstruct_builder *builder, size_t byte_offset, uint8_t value) {
  if (byte_offset + 1 > builder->msg_size) return -1;

  *((char*)(builder->buf + byte_offset)) = *((char*)&value);

  return 0;
}

static inline int qstruct_builder_set_bool(struct qstruct_builder *builder, size_t byte_offset, int bit_offset, int value) {
  if (byte_offset + 1 > builder->msg_size) return -1;

  if (value) {
    *((uint8_t *)(builder->buf + byte_offset)) |= bit_offset;
  } else {
    *((uint8_t *)(builder->buf + byte_offset)) &= ~bit_offset;
  }

  return 0;
}

static inline int qstruct_builder_set_pointer(struct qstruct_builder *builder, size_t byte_offset, char *value, size_t value_size, int alignment, size_t *output_data_start) {
  size_t data_start;
  uint64_t data_start64, value_size64;

  if (byte_offset + 16 > builder->msg_size) return -1;

  if (alignment == 1 && value_size < 16) {
    data_start = byte_offset + 1;
    *((uint8_t *)(builder->buf + byte_offset)) = (uint8_t) value_size;
  } else {
    data_start = QSTRUCT_ALIGN_UP(builder->msg_size, alignment);
    if (qstruct_builder_expand_msg(builder, data_start + value_size)) return -2;
    data_start64 = (uint64_t)data_start;
    value_size64 = (uint64_t)value_size << 8;
    QSTRUCT_STORE_8BYTE_LE(&value_size64, builder->buf + byte_offset);
    QSTRUCT_STORE_8BYTE_LE(&data_start64, builder->buf + byte_offset + 8);
  }

  if (value) memcpy(builder->buf + data_start, value, value_size);
  if (output_data_start) *output_data_start = data_start;

  return 0;
}

static inline int qstruct_builder_set_raw_bytes(struct qstruct_builder *builder, size_t byte_offset, char *value, size_t value_size) {
  if (byte_offset + value_size > builder->msg_size) return -1;

  memcpy(builder->buf + byte_offset, value, value_size);

  return 0;
}

#endif
