//
//  RapidCRC.c
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

#include "RapidCRC.h"

#define POLY64REV     0x95AC9329AC4BC9B5ULL

static uint64_t crc_table[8][256];

#ifdef __cplusplus
extern "C" {
#endif
    
    void init_crc_table_for_oom(void)
    {
        uint64_t c;
        int n, k;
        static int first = 1;
        if(first){
            first = 0;
            for (n = 0; n < 256; n++)
            {
                c = (uint64_t)n;
                for (k = 0; k < 8; k++)
                {
                    if (c & 1)
                        c = (c >> 1) ^ POLY64REV;
                    else
                        c >>= 1;
                }
                crc_table[0][n] = c;
            }
            for (n = 0; n < 256; n++) {
                c = crc_table[0][n];
                for (k = 1; k < 8; k++) {
                    c = crc_table[0][c & 0xff] ^ (c >> 8);
                    crc_table[k][n] = c;
                }
            }
        }
    }
    
    uint64_t rapid_crc64(uint64_t crc, const char *buf, uint64_t len)
    {
        register uint64_t *buf64 = (uint64_t *)buf;
        register uint64_t c = crc;
        register uint64_t length = len;
        c = ~c;
        while (length >= 8) {
            c ^= *buf64++;
            c = crc_table[0][c & 0xff] ^ crc_table[1][(c >> 8) & 0xff] ^ \
                crc_table[2][(c >> 16) & 0xff] ^ crc_table[3][(c >> 24) & 0xff] ^\
                crc_table[4][(c >> 32) & 0xff] ^ crc_table[5][(c >> 40) & 0xff] ^\
            crc_table[6][(c >> 48) & 0xff] ^ crc_table[7][(c >> 56) & 0xff];
            length -= 8;
        }
//        buf = (char *)buf64;
//        while (length > 0) {
//            crc = (crc >> 8) ^ crc_table[0][(crc & 0xff) ^ *buf++];
//            length--;
//        }
        c = ~c;
        return c;
    }
    
#ifdef __cplusplus
}
#endif
