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
 * Modify CC2420CsmaP.nc. The author are ...
 */

#include <stdio.h>
#include <stdint.h>
#include <UserButton.h>

module PriorityMACP @safe() {

  provides interface SplitControl;
  provides interface Receive;
  provides interface Init;
  provides interface Send as SendCSMA; //2012-05-31
  provides interface PMACSlot; //for calculating delay.
  //provides interface RadioBackoff;

  uses interface Resource;
  uses interface CC2420Power;
  uses interface StdControl as SubControl;
  uses interface CC2420Transmit;
  //uses interface RadioBackoff as SubBackoff;
  uses interface Random;
  uses interface Leds;
  uses interface CC2420Packet;
  uses interface CC2420PacketBody;
  uses interface State as SplitControlState;
  //uses interface Boot;
  //uses interface Timer<TMilli>;
  //uses interface Alarm<TMicro,uint16_t> as SlotAlarm;
  //uses interface Alarm<TMicro,uint16_t> as CCAAlarm;
  //uses interface LocalTime<TMicro> as MicroTimer;
  uses interface Receive as SubReceive;
  
  uses interface PacketTimeSyncOffset;
  uses interface PacketTimeStamp<T32khz,uint32_t> as PacketTimeStamp32khz;
  uses interface PMACQueue;

  uses interface GeneralIO as CCA;
  uses interface Notify<button_state_t>;
  uses interface Alarm<T32khz,uint16_t> as Alarm32k;

  uses interface CC2420Config;

}

implementation {

  enum {
    S_STOPPED,
    S_STARTING,
    S_STARTED,
    S_STOPPING,
    S_TRANSMITTING,
  };

  enum{
    ST_SLOT,
    ST_HPIS_END,
    ST_HPIS_CCA,
    ST_SLOT_SUBSLOT,
    //ST_HPIS_ONE,
    //ST_HPIS_TWO,
 };    

 enum{
    DESTI_NODE = 11,
    ROOT_ID = 1,
    //FIRST_SYNC_NODE_ID = 2,
 };

 
 enum{
    NUM_CHANNELS = 15, //16,
    PMAC_DATA_LEN = 20,// 28 +14 = 42,  //13+66 +1 = 80, len = 79.
          //76, //13+76 +1 = 90 including len. TOSH_DATA_LENGTH,
  };

 enum{
    NODE_NUM = 30,
    LAMDA_TCONE = 100, //20
    LAMDA_TCTWO = 120, //400 
    LAMDA_TCFOUR = 100,//30, //%, 30%
    SLOT_LEN = NUM_SUB_SLOT,
  };

 //LinearTableItem   linearTable[MAX_ENTRIES];
 //uint8_t linearTableItemIndex;
 //uint16_t ActiveLinearTable;
 //double slope;
 //double intercept;
 //double avrDivid;
 bool isAlreadySync;
 uint8_t slotState;
 //uint64_t referLocaltime, referGlobaltime;
 uint16_t convertToLocalDeltTime(uint16_t globalDeltTime);
 uint16_t getDeltTime(uint16_t preTime,uint16_t nowTime);
 //void updateLinearTable(uint16_t globalDeltTime, uint16_t localDeltTime);
 //bool checkOutliers(uint16_t globalDeltTime, uint16_t localDeltTime);
 //void calculateLinear();
 //void calculateAvrDivid();
 //uint16_t localToGlobal(uint16_t localTime);
 //uint16_t globalToLocal(uint16_t globalTime);
 //bool isReadyLinear;
 //float getDivision(uint64_t a,uint64_t b);
 //void sendReportMsg(uint32_t paraOne, uint32_t paraTwo, int32_t paraThree, int32_t paraFour);
 //void sendTiSyncGoMsg();
 void sendTCOneMsg(uint8_t seqnum);
 void sendWIOneMsg(uint8_t seqnum, uint32_t absltnum,uint8_t subslotPos);

 void sendWITwoMsg(uint8_t seqnum, uint32_t absltnum,uint8_t subslotPos);
 void sendWIThreeMsg(uint8_t seqnum, uint32_t absltnum);

 bool isStartAttemptPoisson(uint16_t lamda);
 bool isTCFourSendProbability();

 uint8_t selectChFromList(uint8_t chIndex);
 //-----------------------------------------------------------------

 // bool sendBusy = FALSE;
  uint16_t seqno;
  uint32_t abSltNum, startSync; //reSltNum
  uint8_t numACK;
  
  message_t sendTimeSyncMsg; 
  //message_t sendTimeSyncGoBMsg;
  //message_t sendTimeSyncBackBMsg;
  message_t sendTimeSyncDebugBMsg;
  message_t tcOneCsmaMsg,wiOneTdmaMsg,wiTwoTdmaMsg,wiThreeTdmaMsg;//TC1 and TC2 
  //message_t sendTimeSyncForwBMsg;

  message_t* ONE_NOK m_msg;
  
  error_t sendErr = SUCCESS;
  
  /** TRUE if we are to use CCA when sending the current packet */
  norace bool ccaOn;
  norace bool isTimeSyncROOT;
  uint8_t reportseqno;
  uint8_t seqnoTCOne, seqnoTCTwo,seqnoTCFour;
  uint16_t tcAccessStart,tcAccessDelay;
  /****************** Prototypes ****************/
  task void startDone_task();
  task void stopDone_task();
  task void sendDone_task();
  //task void sendCSMADone_task();
  
  void shutdown();
  uint32_t globalSlot;
  bool testBool;
  //---------------
  bool csmaTraffic;
  bool tdmaTraffic;
  bool sndMsgBusy;
  bool isReadyGo;

  uint16_t testBodaryLocal;
  uint16_t testBodaryGlobal;
  bool ccaBusyForTCthreeFour;
  uint16_t deferredNum;
  uint8_t ccaNumber;
  void resetCCAdetection();
  //uint8_t numSubSlot;
  bool isReadyTCTwo; //first only TC4, after press and release button, also TC2.

  uint8_t pressNum;
  uint16_t lamdaTCFour; //,lamdaTCTwo;
  uint16_t global_seqnum;
  uint8_t channelList[NUM_CHANNELS];
  
  /****************** Software Init ********************/
  command error_t Init.init() {
    //uint8_t i;
    //testBool = FALSE;
    /*call Leds.led0Off();
    call Leds.led1Off();
    call Leds.led2Off();*/
    atomic isAlreadySync = FALSE;
    global_seqnum = 0;
    /*for(i=0;i<MAX_ENTRIES;i++){
       linearTable[i].globalDeltTime = 0;
       linearTable[i].localDeltTime = 0;
    }
    globalSlot = 0;*/
    atomic abSltNum = 1;
    startSync = 1;
    atomic numACK = 0;
    //atomic linearTableItemIndex = 0;
    //atomic slope = 0;
    //atomic intercept = 0;
    //atomic avrDivid = 0;
    //atomic isReadyLinear = FALSE;
    //atomic reportseqno = 0;
    atomic seqnoTCOne = 0;
    atomic seqnoTCTwo = 0;
    atomic seqnoTCFour = 0;
    //ActiveLinearTable = 0;
    //atomic csmaTraffic = FALSE;
    //atomic tdmaTraffic = FALSE;
    atomic sndMsgBusy = FALSE;
    //atomic isReadyGo = FALSE;
    resetCCAdetection();
    //atomic numSubSlot = 0;
    
    atomic tcAccessDelay = 0;
    atomic pressNum = 0;
    atomic lamdaTCFour = LAMDA_TCFOUR; // 
    //atomic lamdaTCTwo = LAMDA_TCTWO;
    atomic testBodaryLocal = 0;
    atomic testBodaryGlobal = 0;
    deferredNum = 0;

    channelList[0] = 15;
    channelList[1] = 23;
    channelList[2] = 20;
    channelList[3] = 18;
    channelList[4] = 24;
    channelList[5] = 13;
    channelList[6] = 19;
    channelList[7] = 12;
    channelList[8] = 14;
    channelList[9] = 22;
    channelList[10] = 11;
    channelList[11] = 16;
    channelList[12] = 21;
    channelList[13] = 17;
    channelList[14] = 25;
    //channelList[15] = 26;
    
    
    call Notify.enable();
    return SUCCESS;
  }
  /***************** SplitControl Commands ****************/
  command error_t SplitControl.start() {
    if(call SplitControlState.requestState(S_STARTING) == SUCCESS) {
      call CC2420Power.startVReg();
      return SUCCESS;
    
    } else if(call SplitControlState.isState(S_STARTED)) {
      return EALREADY;
      
    } else if(call SplitControlState.isState(S_STARTING)) {
      return SUCCESS;
    }

    
    
    return EBUSY;
  }

  command error_t SplitControl.stop() {
    if (call SplitControlState.isState(S_STARTED)) {
      call SplitControlState.forceState(S_STOPPING);
      shutdown();
      return SUCCESS;
      
    } else if(call SplitControlState.isState(S_STOPPED)) {
      return EALREADY;
    
    } else if(call SplitControlState.isState(S_TRANSMITTING)) {
      call SplitControlState.forceState(S_STOPPING);
      // At sendDone, the radio will shut down
      return SUCCESS;
    
    } else if(call SplitControlState.isState(S_STOPPING)) {
      return SUCCESS;
    }
    
    return EBUSY;
  }

 
  /***************** Send Messages to lower layer ****************/
  void sendMessage( message_t* p_msg) {
    //uint16_t tmpfcf;
    cc2420_header_t* header = call CC2420PacketBody.getHeader( p_msg );
    cc2420_metadata_t* metadata = call CC2420PacketBody.getMetadata( p_msg );
    //call Leds.led2Toggle();
    atomic {
      if (!call SplitControlState.isState(S_STARTED)) {
        if((header->type == WIMAC_ONE) || (header->type == WIMAC_ZERO) ||
           (header->type == WIMAC_TWO) ||(header->type == WIMAC_THREE)){
           //sndMsgBusy = FALSE;
           //why there is a possibility to be EALREADY?
           atomic sendErr = EALREADY;
           post sendDone_task();
           //signal SendCSMA.sendDone(p_msg, EALREADY);
        }
        return;
      }
      call SplitControlState.forceState(S_TRANSMITTING);
      m_msg = p_msg;
    }
    
    //if unicast: ACK is required.  Not ACK in default.
    if(header->dest != AM_BROADCAST_ADDR)//AM_BROADCAST
       header->fcf |= 1 << IEEE154_FCF_ACK_REQ;

#ifdef CC2420_HW_SECURITY
    header->fcf &= ((1 << IEEE154_FCF_ACK_REQ)|
                    (1 << IEEE154_FCF_SECURITY_ENABLED)|
                    (0x3 << IEEE154_FCF_SRC_ADDR_MODE) |
                    (0x3 << IEEE154_FCF_DEST_ADDR_MODE));
#else
    header->fcf &= ((1 << IEEE154_FCF_ACK_REQ) | 
                    (0x3 << IEEE154_FCF_SRC_ADDR_MODE) |
                    (0x3 << IEEE154_FCF_DEST_ADDR_MODE));
#endif
    header->fcf |= ( ( IEEE154_TYPE_DATA << IEEE154_FCF_FRAME_TYPE ) |
		     ( 1 << IEEE154_FCF_INTRAPAN ) ); 


    metadata->ack = FALSE; //is acked or not.
    metadata->rssi = 0;
    metadata->lqi = 0;
    //metadata->timesync = FALSE;
    //weishen, see msg_metadata->timestamp
    //metadata->timestamp = CC2420_INVALID_TIMESTAMP;

    ccaOn = FALSE;

    //atomic
    if(call CC2420Transmit.send( p_msg, ccaOn ) == SUCCESS){
      atomic sndMsgBusy = TRUE;
      //if(header->type == PMAC_TIMESYNC_GO_BMSG)
        //call PacketTimeSyncOffset.set(p_msg);      
      //seqno ++;
    }
    else
      ;//call Leds.led0Toggle();
  }

 
  //uint32_t start_time_mcro;
  uint8_t nCounter,rcvNum;
  bool bReport;

  void resetCCAdetection(){
    atomic{
       ccaBusyForTCthreeFour = FALSE;
       ccaNumber = 0; 
    }
  }
  
  /*async event void SlotAlarm.fired() {
     
  }*/

  uint16_t globalNow;

  uint16_t debugPoissionTime;
  async event void Alarm32k.fired() {
    uint8_t tempNum; //
    uint16_t now = call Alarm32k.getNow();
    atomic{
      if(isAlreadySync){

         abSltNum++;

         globalNow = now;

		   //call Alarm32k.startAt(now,SUB_SLOT_TIME); //NUM_SUB_SLOT == 22
                   call Alarm32k.startAt(now,SLOT_TIME);
		   slotState =  ST_SLOT;

		   //detect loseSync:
                   if(abSltNum - startSync > INTERVAL_LOSE_SYNC){
                       isAlreadySync = FALSE;
                       call Leds.led1Off();
                       return;
                   }

  
                   if(abSltNum % INTERVAL_TIMESYNC == SLOT_FOR_TIMESYNC ){
		      //reserve for receiving time sync packet.
		      atomic sndMsgBusy = TRUE; //differentiate setCh(26) and others
		      call CC2420Config.setChannel(26);
		      if(call CC2420Config.sync() != SUCCESS)
			    call Leds.led0Toggle();
		   }
                   else if(abSltNum % INTERVAL_TIMESYNC == SLOT_FOR_REPORT){
                       //if(!sndMsgBusy){
		          //printf("%u,%u,%u,%u\r\n",FRAME_TIME- 
                           //  testBodaryLocal,globalNow,testBodaryLocal,testBodaryGlobal);
                        /*if(testBodaryLocal!=0)
                          printf("%u,%u,%lu,%hu\r\n",FRAME_TIME- 
                             testBodaryLocal,testBodaryGlobal,abSltNum,deferredNum);

    			  testBodaryLocal = 0;
    			  testBodaryGlobal = 0;
			  debugPoissionTime = 0;*/
		          //call Leds.led0Toggle();
                   }
                   else{
                       if(abSltNum % INTERVAL_SUPERFRAME == TOS_NODE_ID){
		           uint8_t nxtChannel;
			   atomic sndMsgBusy = FALSE;
		           //change channel:
                       	   nxtChannel = selectChFromList(
				(abSltNum/INTERVAL_SUPERFRAME+1)%NUM_CHANNELS);
		           //nxtChannel = global_seqnum%NUM_CHANNELS + 11;
		           call CC2420Config.setChannel(nxtChannel);
		           if(call CC2420Config.sync() != SUCCESS)
			        call Leds.led0Toggle();
                       }
                   }

      }//if(isAlreadySync)
      else{
        abSltNum++;
        //globalNow = now;
        call Alarm32k.startAt(now,SLOT_TIME);
      }
    }//atomic

  }
  
  event void CC2420Config.syncDone(error_t error){

      if(error == SUCCESS && !sndMsgBusy){
           //for multihop case:
           //call PMACQueue.readyPush(abSltNum);
           //single hop case:
	   //printf("send channel:%hu\r\n",call CC2420Config.getChannel());
	   sendWIThreeMsg(global_seqnum, abSltNum);
	   //call Leds.led2Toggle();


      }


  }

  uint8_t selectChFromList(uint8_t chIndex){
      if(chIndex == 0)
	chIndex = 15;
      return channelList[chIndex-1];

  }


  /***************** SubReceive Events *****************/
  event message_t *SubReceive.receive(message_t* msg, void* payload, 
      uint8_t len) {

    cc2420_header_t* header = call CC2420PacketBody.getHeader(msg);
    //uint8_t type = (call CC2420PacketBody.getHeader(msg))->type;
    //TimeSyncBMsg * rcvtimeMsg = (TimeSyncBMsg*)(payload);
    //PacketTimeStamp32khz: in fact it is 1Mhz and the timestamp is 16 bits:
    
    
    if(header->type == PMAC_TIMESYNC_BMSG && (header->src == 1) ){
                         // && (header->length == 13+sizeof(TimeSyncBMsg))){
       //uint16_t rxTime;
       uint16_t timestamp = call PacketTimeStamp32khz.timestamp(msg); //timeSFD.
       TimeSyncBMsg * rcvtimeMsg = (TimeSyncBMsg*)(payload);
       //uint16_t now;

       if(timestamp == 0){
	   atomic testBodaryGlobal = rcvtimeMsg->timestamp;
           return msg;
       }
       
       
       //--for time sync accuracy report---------------
      atomic{
       testBodaryLocal = getDeltTime(globalNow,timestamp);//rcv SFD time
       testBodaryGlobal = rcvtimeMsg->timestamp;//sender: fired Time - SFD time
       
      }
      //|(SFD)----------|(now)------|(globalFired)  
      call Alarm32k.startAt(timestamp,rcvtimeMsg->timestamp); 
      atomic{
         abSltNum = rcvtimeMsg->absltnum;
         if(!isAlreadySync){
             call Leds.led1On();
             isAlreadySync = TRUE;
         }
         startSync = abSltNum;

       }
      
          //never happen:
          //|(RX_SFD)----------------------|(globalFired)------|(now)
          //|<---rcvtimeMsg->timestamp---->|
          //|<-----------------------rxTime------------------->|
    

       return msg; //do not need signal to upper layer!
    }

    return signal Receive.receive(msg, payload, len);
  }
  


  /**************** Events **************************************************/
  uint32_t end_time_mcro;  //when TC1, TC2, TC3 or TC4 is sent out, signal sendDone.
  async event void CC2420Transmit.sendDone( message_t* p_msg, error_t err ) {
    
    uint8_t type = (call CC2420PacketBody.getHeader(p_msg))->type;
    atomic sendErr = err;
    //call Leds.led2Toggle();
    //atomic{
      //end_time_mcro = call SlotAlarm.getNow();//call MicroTimer.get();
      //printf("end sndMsg:%lu,difference:%lu.\r\n",end_time_mcro,end_time_mcro-start_time_mcro);
    //}
    atomic sndMsgBusy = FALSE;
    atomic m_msg = p_msg;

    if(err == SUCCESS && (type == WIMAC_TWO))
      call Leds.led0Toggle();
    else if(err == SUCCESS && (type == WIMAC_THREE)){
      global_seqnum++;
      call Leds.led0Toggle();
    }

    post sendDone_task();

    
  }

  async event void CC2420Power.startVRegDone() {
    call Resource.request();
  }
  
  event void Resource.granted() {
    call CC2420Power.startOscillator();
  }

  async event void CC2420Power.startOscillatorDone() {
    post startDone_task();
  }
 
  
  
  /***************** Tasks ****************/
  task void sendDone_task() {
    error_t packetErr;
    uint8_t type;
    atomic type = (call CC2420PacketBody.getHeader(m_msg))->type;
    atomic packetErr = sendErr;
    if(call SplitControlState.isState(S_STOPPING)) {
      shutdown();
      
    } else {
      //call Leds.led2Toggle();
      call SplitControlState.forceState(S_STARTED);
    }

    atomic debugPoissionTime = abSltNum; //getDeltTime(globalNow,call Alarm32k.getNow());
    signal PMACSlot.sendDone(packetErr,type);

    //if(packetErr == SUCCESS)
      // atomic numACK++;
    
    //signal Send.sendDone( m_msg, packetErr );
  }
  

  task void startDone_task() {
    call SubControl.start();
    call CC2420Power.rxOn();
    call Resource.release();
    call SplitControlState.forceState(S_STARTED);
    signal SplitControl.startDone( SUCCESS );
    //weishen:  be able to transmit.
    atomic seqno = 0;
    atomic nCounter = 0;
    atomic bReport = FALSE;
    atomic rcvNum = 0;
    atomic abSltNum = 1;
    
    if(TOS_NODE_ID == ROOT_ID)
      atomic isTimeSyncROOT = TRUE;
    call Alarm32k.startAt((call Alarm32k.getNow()),SLOT_TIME);
  }
  
  task void stopDone_task() {
    call SplitControlState.forceState(S_STOPPED);
    signal SplitControl.stopDone( SUCCESS );
  }
  
  
  /***************** Functions ****************/
  /**
   * Shut down all sub-components and turn off the radio
   */
  void shutdown() {
    call SubControl.stop();
    call CC2420Power.stopVReg();
    post stopDone_task();
  }

//-----------generatetc1 generatetc2 sendtc1 sendtc2 ,sending in MAC layer impl.---------
  void genWIOnePkt(message_t* p_msg, uint8_t seqnum){

       cc2420_header_t* header = call CC2420PacketBody.getHeader( p_msg );
       header->type = WIMAC_ONE; //PMAC_TIMESYNC_DEBUG_BMSG;
       header->dest = DESTI_NODE; //AM_BROADCAST_ADDR;
       //header->destpan = call CC2420Config.getPanAddr();
       header->src = TOS_NODE_ID;
       header->fcf |= ( 1 << IEEE154_FCF_INTRAPAN ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_DEST_ADDR_MODE ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_SRC_ADDR_MODE );
       //CC2420_SIZE = 13. sizeof(TimeSyncReportBMsg) = 16.
       //in printf, len = 29. lenth DOES not include itself. 
       header->length = CC2420_SIZE + PMAC_DATA_LEN;////sizeof(TimeSyncReportBMsg) + CC2420_SIZE + EXTR_REPORT_PACKET_LEN;
       atomic header->dsn = seqnum; //seqnoTCTwo++;  //
  }
  
  void genTCOnePkt(message_t* p_msg, uint8_t seqnum){

       cc2420_header_t* header = call CC2420PacketBody.getHeader( p_msg );
       header->type = PMAC_TC_ONE_UMSG; //PMAC_TIMESYNC_DEBUG_BMSG;
       header->dest = DESTI_NODE;//AM_BROADCAST_ADDR;
       //header->destpan = call CC2420Config.getPanAddr();
       header->src = TOS_NODE_ID;
       header->fcf |= ( 1 << IEEE154_FCF_INTRAPAN ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_DEST_ADDR_MODE ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_SRC_ADDR_MODE );
       //CC2420_SIZE = 13. sizeof(TimeSyncReportBMsg) = 16.
       //in printf, len = 29. lenth DOES not include itself. 
       header->length = CC2420_SIZE + PMAC_DATA_LEN;////sizeof(TimeSyncReportBMsg) + CC2420_SIZE + EXTR_REPORT_PACKET_LEN;
       atomic header->dsn = seqnum; //seqnoTCOne++;  //
  }

  void sendWIOneMsg(uint8_t seqnum, uint32_t absltnum,uint8_t subslotPos){

       //---------------------------------------------------------------------
       TCTdmaUMsg *wiOneMsg = (TCTdmaUMsg *)((&wiOneTdmaMsg)->data);

       atomic wiOneMsg->absltnum = absltnum;
       atomic wiOneMsg->accessDelay = subslotPos*SUB_SLOT_TIME; //accessDelay;
		//getDeltTime(globalNow,call Alarm32k.getNow());

       genWIOnePkt(&wiOneTdmaMsg,seqnum); 
       sendMessage(&wiOneTdmaMsg);
  }

  void sendTCOneMsg(uint8_t seqnum){

       TCTdmaUMsg *tcOneMsg = (TCTdmaUMsg *)((&tcOneCsmaMsg)->data);

       atomic tcOneMsg->absltnum = abSltNum;
       atomic tcOneMsg->accessDelay = tcAccessDelay; //accessDelay;
            //getDeltTime(globalNow,call Alarm32k.getNow());

       genTCOnePkt(&tcOneCsmaMsg, seqnum); 
       sendMessage(&tcOneCsmaMsg);
  }

  //-------------------------------------------------------------------------
  void genWIThreePkt(message_t* p_msg, uint8_t seqnum){

       cc2420_header_t* header = call CC2420PacketBody.getHeader( p_msg );
       header->type = WIMAC_THREE; //PMAC_TIMESYNC_DEBUG_BMSG;
       header->dest = DESTI_NODE;
       //header->destpan = call CC2420Config.getPanAddr();
       header->src = TOS_NODE_ID;
       header->fcf = 0;
       header->fcf |= ( 1 << IEEE154_FCF_INTRAPAN ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_DEST_ADDR_MODE ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_SRC_ADDR_MODE );
       //CC2420_SIZE = 13. sizeof(TimeSyncReportBMsg) = 16.
       //in printf, len = 29. lenth DOES not include itself. 
       header->length = CC2420_SIZE + PMAC_DATA_LEN;////sizeof(TimeSyncReportBMsg) + CC2420_SIZE + EXTR_REPORT_PACKET_LEN;
       atomic header->dsn = seqnum; //seqnoTCFour++;  //
  }
  void sendWIThreeMsg(uint8_t seqnum, uint32_t absltnum){

       TCTdmaUMsg *wiThreeMsg = (TCTdmaUMsg *)((&wiThreeTdmaMsg)->data);

       atomic wiThreeMsg->absltnum = absltnum; //abSltNum;
       //may be set to 27:
       atomic wiThreeMsg->accessDelay = getDeltTime(globalNow,call Alarm32k.getNow());
       
       genWIThreePkt(&wiThreeTdmaMsg,seqnum); 
       sendMessage(&wiThreeTdmaMsg);
  }

  //-------------------------------------------------------------------------
  void genWITwoPkt(message_t* p_msg, uint8_t seqnum){

       cc2420_header_t* header = call CC2420PacketBody.getHeader( p_msg );
       header->type = WIMAC_TWO; //PMAC_TIMESYNC_DEBUG_BMSG;
       header->dest = DESTI_NODE;
       //header->destpan = call CC2420Config.getPanAddr();
       header->src = TOS_NODE_ID;
       header->fcf |= ( 1 << IEEE154_FCF_INTRAPAN ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_DEST_ADDR_MODE ) |
         ( IEEE154_ADDR_SHORT << IEEE154_FCF_SRC_ADDR_MODE );
       //CC2420_SIZE = 13. sizeof(TimeSyncReportBMsg) = 16.
       //in printf, len = 29. lenth DOES not include itself. 
       header->length = CC2420_SIZE + PMAC_DATA_LEN;////sizeof(TimeSyncReportBMsg) + CC2420_SIZE + EXTR_REPORT_PACKET_LEN;
       atomic header->dsn = seqnum; //seqnoTCThree++;  //
  }
  void sendWITwoMsg(uint8_t seqnum, uint32_t absltnum,uint8_t subslotPos){

       TCTdmaUMsg *wiTwoMsg = (TCTdmaUMsg *)((&wiTwoTdmaMsg)->data);

       atomic wiTwoMsg->absltnum = absltnum;
       atomic wiTwoMsg->accessDelay = subslotPos*SUB_SLOT_TIME; //accessDelay;
		//getDeltTime(globalNow,call Alarm32k.getNow());
       
       genWITwoPkt(&wiTwoTdmaMsg,seqnum); 
       sendMessage(&wiTwoTdmaMsg);
  }
//------------------------------------------------------------------------------------
  

  uint16_t getDeltTime(uint16_t preTime,uint16_t nowTime){
     if(nowTime>preTime)
        return nowTime-preTime;
     else
        return 0xffff-preTime+nowTime;
  }


  //----------------------CSMA Impl.-----------------------------------------------------
  void genCSMAPkt(message_t* p_msg, uint8_t len){
    
        
  }

  
  command error_t SendCSMA.send(message_t *msg, uint8_t len) {
     
     return SUCCESS;
     
        
  }
  command error_t SendCSMA.cancel(message_t *msg) {
    //return call SubSend.cancel(msg); //delete in the queue
    return TRUE;
  }
  
  
  command uint8_t SendCSMA.maxPayloadLength() {
    return TOSH_DATA_LENGTH; //cc2420CsmaP, call SubSend.maxPayloadLength();
  }

  command void *SendCSMA.getPayload(message_t* msg, uint8_t len) {
    if (len <= TOSH_DATA_LENGTH) {
      return (void* COUNT_NOK(len ))(msg->data);
    }
    else {
      return NULL;
    }
    //return call SubSend.getPayload(msg, len);
  }
 
  async command error_t PMACSlot.pushPacket(uint8_t type, uint8_t seqnum, 
                                            uint32_t absltnum,uint8_t subslotPos){
     
     atomic{
       if(!isAlreadySync) return FAIL;
       if(ccaBusyForTCthreeFour){
          //call Leds.led2Toggle();
          deferredNum++;
          return FAIL; //no neccessary to decrease rest reTxCount.
       }
     }

     //atomic
       //debugPoissionTime = getDeltTime(globalNow,call Alarm32k.getNow());

     switch(type){
        case WIMAC_ZERO:
          sendTCOneMsg(seqnum);
          break;
        case WIMAC_ONE:
	  
          sendWIOneMsg(seqnum, absltnum, subslotPos);
          break;
        case WIMAC_TWO:
          sendWITwoMsg(seqnum, absltnum, subslotPos);
          break;
        case WIMAC_THREE:
          //sendwiThreeMsg(seqnum);
          sendWIThreeMsg(seqnum, absltnum);
          break;
        default:
          break;

     }
     return SUCCESS;
  }
  async command error_t PMACSlot.prolongTimer(){

    if(slotState == ST_SLOT){
       uint16_t alarmTime = call Alarm32k.getAlarm();
       uint16_t now = call Alarm32k.getNow();
       call Alarm32k.stop();
       call Alarm32k.startAt(now,getDeltTime(now,alarmTime)+SLOT_TIME);
    }

    return SUCCESS;

  }

  bool isStartAttemptPoisson(uint16_t lamda)  //for TC1, TC2 or TC3.
   {
      uint32_t res;
      uint32_t random = call Random.rand32(); //[0,4294967295]
      //uint32_t mask = 100000000;
      uint32_t propa = (uint32_t)lamda*NODE_NUM*SLOT_LEN*INTERVAL_SUPERFRAME; 
      //e.g., 30*12800*22 = 8448000;  30* 3200 *22 = 2112000
      //propa = (uint16_t)(100000000.0/propa);//e.g., 100000000.0/8448000 = 11.8 = 11
      //debug
      //if(propa == 13) call Leds.led2Toggle(); //13 --- lamda = 10, 6 -- lamda = 20
      //else call Leds.led0Toggle();
    
      res = random%propa;//
      /*res = (uint16_t)random/propa * propa;
      if(res == random) res = 0;*/

      if(res == 0) return TRUE;
      else return FALSE;

  }
  /*bool isStartAttemptPoisson(uint16_t lamda)  //for TC1 and TC2.
  {
    uint32_t res = call Random.rand32(); //[0,4294967295]
    uint32_t mask = 100000;
    uint16_t propa = NODE_NUM*lamda*SLOT_LEN; //e.g., 30*10*25 = 7500 λ
    propa = (uint16_t)(100000.0/propa);//e.g., 100000.0/7500 = 13.3 = 13
    //debug
    //if(propa == 13) call Leds.led2Toggle(); //13 --- lamda = 10, 6 -- lamda = 20
    //else call Leds.led0Toggle();
    
    res = res%mask;//

    if(res<=propa) return TRUE;
    else return FALSE;

  }*/

  bool isTCFourSendProbability(){
    uint8_t lamda;
    uint32_t res = call Random.rand32(); //[0,4294967295]
    uint8_t mask = 100;
    res = res%mask;
    
    atomic lamda = lamdaTCFour;
    //lamda must be [1,100]
    if(lamda == 100) return TRUE;
    if(res<=lamda) return TRUE;
    else return FALSE;
     
  }
  
  event void Notify.notify( button_state_t state ) {
    if ( state == BUTTON_PRESSED ) {
      //call Leds.led2On();
    
       pressNum++;
       switch(pressNum){
         /*case 0:
           call Leds.led0On();
           call Leds.led1Off();
           call Leds.led2Off();
           atomic lamdaTCFour = 100;
           break;*/
         case 1:
           call Leds.led0On();  //modify four points
           //call Leds.led2Off();
           atomic lamdaTCFour = 90;
           break;
         case 2:
           call Leds.led0On();  //modify four points
           //call Leds.led2On();
           atomic lamdaTCFour = 80;
           break;
         case 3:
           call Leds.led0On();
           atomic lamdaTCFour = 70;
 
           break;
         case 4:
           call Leds.led0On();
           atomic lamdaTCFour = 60;
 
           break;
         case 5:
       
           call Leds.led0On();
           atomic lamdaTCFour = 50;
  
           break;
         case 6:
       
           call Leds.led0On();
           atomic lamdaTCFour = 40;
      
           break;
         case 7:
   
           call Leds.led0On();
           atomic lamdaTCFour = 30;
     
           break;
         case 8:
       
           call Leds.led0On();
           atomic lamdaTCFour = 20;
     
           break;
         case 9:
       
           call Leds.led0On();
           atomic lamdaTCFour = 10;

           break;
       }
      
    } else if ( state == BUTTON_RELEASED ) {
         call Leds.led0Off();
         call Leds.led1Off();
         call Leds.led2Off();
    }
  }
  /***************** Defaults ***************/
  default event void SplitControl.startDone(error_t error) {
  }
  
  default event void SplitControl.stopDone(error_t error) {
  }

  
}
