#ifndef _QSTRUCT__QSTRUCT_LOADER_H
#define _QSTRUCT__QSTRUCT_LOADER_H

#include <inttypes.h>
#include <stdint.h>

#include "qstruct_utils.h"



static inline int qstruct_sanity_check(char *buf, size_t buf_size) {
  uint64_t body_size;
  if (buf_size < 16) return -1;
  QSTRUCT_LOAD_8BYTE_LE(buf + 8, &body_size);

  if (body_size + 16 > buf_size) return -2;

  return 0;
}


static inline int qstruct_get_uint64(char *buf, size_t buf_size, size_t byte_offset, uint64_t *output) {
  uint64_t body_size;
  if (buf_size < 16) return -1;
  QSTRUCT_LOAD_8BYTE_LE(buf + 8, &body_size);

  if (byte_offset + 8 > body_size + 16 || byte_offset + 8 > buf_size) {
    *output = 0; // default value
  } else {
    QSTRUCT_LOAD_8BYTE_LE(buf + byte_offset, output);
  }

  return 0;
}

static inline int qstruct_get_bool(char *buf, size_t buf_size, size_t byte_offset, int bit_offset, int *output) {
  uint64_t body_size;
  if (buf_size < 16) return -1;
  QSTRUCT_LOAD_8BYTE_LE(buf + 8, &body_size);

  if (byte_offset + 1 > body_size + 16 || byte_offset + 1 > buf_size) {
    *output = 0; // default to false
  } else {
    *output = !!(*((uint8_t *)(buf + byte_offset)) & bit_offset);
  }

  return 0;
}


static inline int qstruct_get_pointer(char *buf, size_t buf_size, size_t byte_offset, char **output, size_t *output_size, int allow_tagged_pointer) {
  uint64_t body_size, length, start_offset;
  if (buf_size < 16) return -1;
  QSTRUCT_LOAD_8BYTE_LE(buf + 8 , &body_size);

  if (byte_offset + 16 > body_size + 16 || byte_offset + 16 > buf_size) {
    *output = 0; // default value
    *output_size = 0;
  } else {
    QSTRUCT_LOAD_8BYTE_LE(buf + byte_offset, &length);

    if (allow_tagged_pointer && length & 0xF) {
      *output = buf + byte_offset + 1;
      *output_size = (size_t)(length & 0xF);
    } else {
      length = length >> 8;
      QSTRUCT_LOAD_8BYTE_LE(buf + byte_offset, &start_offset);
      if (start_offset + length > SIZE_MAX) return -2;
      if (start_offset + length > buf_size) return -1;
      *output = buf + start_offset;
      *output_size = (size_t)length;
    }
  }

  return 0;
}


#endif
