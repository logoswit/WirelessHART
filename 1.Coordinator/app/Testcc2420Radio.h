#ifndef TEST_cc2420Radio_H
#define TEST_cc2420Radio_H
#include "AM.h"

//NOTE:  when change it, copy to printf apps!!!

typedef nx_struct TestTCPMACMsg {
 // nx_am_addr_t source;
 // nx_uint16_t seqno;
 // nx_am_addr_t parent;
  //nx_uint16_t metric;
  nx_uint8_t type;
  nx_uint32_t absSltNum;
  nx_uint16_t timeFromFired;//two steps:1.app getNow; 2.PMACP.nc SendCSMA.send. from HPIS start.
  //nx_uint8_t hopcount;
  //nx_uint16_t sendCount;
  //nx_uint16_t sendSuccessCount;
} TestTCPMACMsg;

#endif
