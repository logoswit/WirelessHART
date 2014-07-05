#ifndef PmacQueue_H
#define PmacQueue_H


typedef struct QueueEntry {
   bool       used;
   uint8_t    retries;
   //message_t* pkt;
   uint8_t    type; //TC1 - TC4
   uint8_t    seqno;
   uint32_t   absltnum;
   uint8_t    subslotPos;
} QueueEntry_t;
//PmacQueue entry definition
/*typedef struct TDMAQueueEntry {
   bool       used;
   uint8_t    retries;
   uint8_t    slotoffset;
   message_t* pkt;
   uint8_t    type;
   uint16_t   addr;
   uint16_t   source;
   uint8_t    len;
} TDMAQueueEntry_t;

typedef struct CSMAQueueEntry {
   bool       used;
   uint8_t    retries;
   message_t* pkt;
   uint8_t    type;
   uint16_t   addr;
   uint16_t   source;
   uint8_t    len;
} CSMAQueueEntry_t;*/

/*typedef struct DequeueEntry {
	   bool    found;
	   uint8_t type;
	   uint16_t addr;
	   message_t* msg;
	   uint8_t len;
} DequeueEntry_t;
   
typedef struct {
  //am_addr_t parentid;
  uint8_t linkType;  //1, outbound link; 0 inbound link
  am_addr_t srcId;
  am_addr_t parentOrChildId;
  uint8_t sltoffset;
  uint8_t choffset;
} schedule_table_entry;*/

enum {
  MAX_TDMA_RETRIES_NUM = 5,//10, //5, //weishen , 30
  MAX_CSMA_RETRIES_NUM = 30,//10, //5, //weishen , 30
  MAX_TDMAQUEUELEN = 30,
  MAX_CSMAQUEUELEN = 5,
};

#endif
