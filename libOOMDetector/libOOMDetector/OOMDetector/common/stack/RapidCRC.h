//
//  RapidCRC.h
//  OOMDetector
//
//  Tencent is pleased to support the open source community by making OOMDetector available.
//  Copyright (C) 2017 THL A29 Limited, a Tencent company. All rights reserved.
//  Licensed under the MIT License (the "License"); you may not use this file except
//  in compliance with the License. You may obtain a copy of the License at
//
//  http://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//

#ifndef CRC64_h
#define CRC64_h

#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif
    extern void init_crc_table_for_oom(void);
    extern uint64_t rapid_crc64(uint64_t crc,  const char *buf, uint64_t len);
//    uint64_t crc64(uint64_t crc, const char *buf, uint64_t len);
//    extern int32_t crc32(uint8_t *bytes);
#ifdef __cplusplus
}
#endif

#endif /* CRC64_h */
