/*
 * Copyright (c) 2012, Mid Sweden University
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE VANDERBILT UNIVERSITY BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE VANDERBILT
 * UNIVERSITY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE VANDERBILT UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE VANDERBILT UNIVERSITY HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 *
 * @author:Wei Shen (wei.shen@miun.se)
 */

//NOTE!!! When change it, has to consider copy some parameters to APP layer ***.h as well.
//
typedef nx_uint16_t timesync16_t;

typedef nx_struct TimeSyncBMsg
{
   //related to CC2420TransmitP.nc absOffset's calculation. weishen
   nx_uint16_t 	timestamp;//deltTime = FiredTime - SFD Time
   //nx_uint8_t 	startNodeid;
   //nx_bool isSyncEnd;
   //nx_uint32_t 	timestampc;
   nx_uint32_t	absltnum; 
} TimeSyncBMsg;


typedef nx_struct TCCsmaBMsg   //TC1 and TC2
{
   nx_uint32_t	absltnum; 
   nx_uint16_t  accessDelay;
} TCCsmaBMsg;

typedef nx_struct TCTdmaUMsg   //TC3 and TC4
{
   nx_uint32_t	absltnum; 
   nx_uint16_t  accessDelay;
} TCTdmaUMsg;

//for coordinator:
typedef struct RecordPacket   //TC3 and TC4
{
   bool        used;
   uint16_t    src; 
   //uint8_t     pre_seqno;
   uint8_t     seqno;
   uint8_t     txCount;
   uint16_t    delay1;
   uint16_t    delay2;
   uint32_t    delay3;
   
} RecordPacket;

//NOTE: related to Testcc2420RadioP.nc in App layer.
enum{//MSGs in upper layer.
   PMAC_TIMESYNC_BMSG = 0x8E,
   PMAC_TC_ONE_UMSG = 0x3A,
   PMAC_TC_TWO_UMSG = 0x3B,
   PMAC_TC_THREE_UMSG = 0x3C,
   PMAC_TC_FOUR_UMSG = 0x3D,
   WIMAC_ZERO = 0x4D,
   WIMAC_ONE = 0x4A,
   WIMAC_TWO = 0x4B,
   WIMAC_THREE = 0x4C,
};

enum{
   PMAC_MINBE = 0x03,
   PMAC_MAXBE = 0x05,
};

enum{
   WI0_MAXRE = 10,
   WI1_MAXRE = 10, //PriorityMACQueueP.nc
   WI2_MAXRE = 10,
   WI3_MAXRE = 10,
};


enum{
  INTERVAL_TIMESYNC = 48, //2 superframe
  INTERVAL_SUPERFRAME = 24, //22, //
  //INTERVAL_DEBUG = 192,
  //for coordinator:
  INTERVAL_COOR_PDR_WINSIZE = 50, //100 superframe.
  INTERVAL_LOSE_SYNC = 8*INTERVAL_TIMESYNC,
};

enum{
  SLOT_FOR_TIMESYNC = 1,//1,
  SLOT_FOR_REPORT = 20, //+TOS_NODE_ID which starts from 2. NODE 2 -- NODE14. So slotoffset is: 3, 4, ..., 16 
  //SLOT_FOR_
};


//a frame is composed of a HPIS + a slot.
enum{ //NOTE: related to Testcc2420RadioP.nc in App layer.
     FRAME_TIME = 330, //367,//in 2"15,=(10875+870)/32;
                            // = 11744, actually the microtimer, get 11703
     SLOT_TIME = 330, //340,//in2¨15, 10875,//11600, //ticks in TMicro. 10.371ms
     HPIS_TIME = 0, //27,//in 2¨15, 870, //600 indication, 135 == 128 us.270 CCA.
     SUB_SLOT_TIME = 15, // == 480 microticks, 435,
     NUM_SUB_SLOT = 22, // 330/15, 25,//10875/435
     BACKOFF_UNIT = SUB_SLOT_TIME,
};

enum{
     CCA_SAMPLE_TIME = 4,//135, //8 symbol periods = 128 us.= 135 microticks. 1.048576 * 128
     //EXTR_REPORT_PACKET_LEN = 60, //16+60 76 data + 11 hdr + 2 footer = 89 bytes + 1 len = 90.
 };

//PMACQueue
enum{
     NODE_NUM_WITHREE = 20, //WiThree and WiTwo, 2-21
     //NODE_NUM_WITWO = ,  //22 - 30
     NODE_NUM_WIONE = 9, 
     NODE_NUM_WIZERO = 1, //31
     LAMDA_WIZERO = INTERVAL_SUPERFRAME*256, //14080*4 = 56320 ms
     LAMDA_WIONE = INTERVAL_SUPERFRAME*64, // 14080 ms
     LAMDA_WITWO = INTERVAL_SUPERFRAME*32, //704 frames.
     //INTERVAL_TCFOUR = INTERVAL_SUPERFRAME,//16 superframes, 16*220 = 3520 ms
     SLOT_LEN = NUM_SUB_SLOT,
     //for change refresh intervals:
     INTERVAL_CH_INTERVAL = INTERVAL_SUPERFRAME * 30039L,
     NUM_FRESH_INTERVALS = 8,
};


