
#include "PmacQueue.h"

module PriorityMACQueueP { ////tdmaQueue[i].type = amId; (am_id_t amId)
   provides interface Init as SoftwareInit;
   /*provides interface Send as SendDATA;
   provides interface SimpleSend as SendKA;
   provides interface SimpleSend as SendRES;
   provides interface SimpleSend as SendADV;*/
   provides interface Send; //weishe
   provides interface PMACQueue;  //
   uses interface PacketAcknowledgements;
   uses interface CC2420PacketBody;
   //provides interface DebugPrint;
   //uses interface GlobalTime;
   //uses interface GlobalSynch;
   //uses interface PrintPacket;
   //uses interface ActiveMessageAddress;
   //uses interface AMSend; //weishe
   //uses interface Send as SendCSMA;
   uses interface Leds;

   uses interface Random;
   uses interface Alarm<T32khz,uint16_t> as SubSlotAlarm32k;
   uses interface PMACSlot;
}
implementation {
   
   //message_t* current_msg;
   //error_t current_error;
   //bool busy;
   bool isPushBusy,isOnePushing,isTwoPushing,isThreePushing,isFourPushing;
   //uint8_t numSubSlot;
   QueueEntry_t wiOne; //twoQueue[2]; //MAX_TDMAQUEUELEN == 13
   //CSMAQueueEntry_t csmaQueue[MAX_CSMAQUEUELEN];

   bool isAttemptPoissonWi1();
   uint8_t getSubslotPosWi1();
   uint8_t getSlotOffset();

   //uint16_t wi3RefreshInterval;

   enum{
     VALUE_ONE = 4,
     VALUE_TWO = 5,

   };

   

//------------------------------------------------------------------------------------------------
  command error_t Send.send(message_t *msg, uint8_t len) {
 
    return TRUE;
     
  }
  command error_t Send.cancel(message_t *msg) {
    //return call SubSend.cancel(msg); //delete in the queue
    return TRUE;
  }
  
  
  command uint8_t Send.maxPayloadLength() {
    return TOSH_DATA_LENGTH; //cc2420CsmaP, call SubSend.maxPayloadLength();
  }

  command void *Send.getPayload(message_t* msg, uint8_t len) {
    if (len <= TOSH_DATA_LENGTH) {
      return (void* COUNT_NOK(len ))(msg->data);
    }
    else {
      return NULL;
    }
    //return call SubSend.getPayload(msg, len);
  }

   //SoftwareInit
   command error_t SoftwareInit.init() {
      uint8_t i;
      dbg("PMACQueueP","%s:initialization!\n",__FUNCTION__);

      wiOne.seqno = 0;

      isPushBusy = FALSE;
      isOnePushing= FALSE;
      isTwoPushing = FALSE;
      isThreePushing = FALSE;
      isFourPushing = FALSE;
      //wi3RefreshInterval = INTERVAL_SUPERFRAME*16;
      //busy=FALSE;
      return SUCCESS;
   }

   
   async command message_t* PMACQueue.getTimeSyncPkt() {
     //return &timesyncpkt;
   }
   
   //DeQueue.done is sent out by the MAC layer. Weishen. Impl. retransmission if not success
   //No need to signal the forwarder.  

   async command void PMACQueue.abortPush(){
       call SubSlotAlarm32k.stop();
   }

   async command void PMACQueue.readyPush(uint32_t abSltNum){

    //bool isTC3Sending = FALSE,isTC2Sending = FALSE,isTC1Sending = FALSE;
    bool isLocalSlot = FALSE;
    uint8_t subslotPos;
    atomic{

          if(abSltNum % INTERVAL_SUPERFRAME == getSlotOffset()){
             isLocalSlot = TRUE;

          }
       
          //TC3:  WiHART1 ----------------------------------------------
          // If the old packet has not sent yet, NOT generate a new packet
          if(!isPushBusy && isAttemptPoissonWi1()){//actually not possible already three pushing

              if(wiOne.used == FALSE){ 

                 subslotPos = getSubslotPosWi1();
                 //if isLocalSlot && there is an old packet, && new packet subslotPos !=0:
	         //otherwise, the old packet would be replaced and new sends "in the future".
                 if(isLocalSlot && wiOne.used && (subslotPos != 0)) // ???
                     subslotPos = 0;
                 //isTC3Sending = isAttemptPoisson(LAMDA_TCTHREE);
                  //if(isTC3Sending){
                 wiOne.used=TRUE;
	         wiOne.retries=WI1_MAXRE;
	         wiOne.type=WIMAC_ONE;
	         wiOne.seqno+=1;
		 wiOne.absltnum = abSltNum;
		 wiOne.subslotPos = subslotPos;
                 //wiOne.abSltNum = abSltNum;
		 //wiOne.subslotPos = subslotPos; 
             }
             else{ //NOT replace, continue transmitting old packet
             }
          }
          //push:
          if(!isPushBusy && isLocalSlot){
	     bool isPush;
             if( wiOne.used ){ //WiHART_1
                    //wiOne.abSltNum, wiOne.subslotPos
	         isPush = call PMACSlot.pushPacket(wiOne.type, wiOne.seqno,
				wiOne.absltnum, wiOne.subslotPos);
		 if(isPush == SUCCESS) isPushBusy = TRUE;  //SUCCESS == 0, FAIL == 1
		 else isPushBusy = FALSE;
             }
          }
     }//atomic
   }

   //each group of Poisson calculations takes about 2 ticks, while there are 15 ticks for subslot
   async event void SubSlotAlarm32k.fired(){
   }



   //INTERVAL_SUPERFRAME*400 = 12800
   bool isAttemptPoissonWi1()  //for TC1, TC2 or TC3.
   {
      uint32_t res;
      uint64_t random = call Random.rand32(); //[0,4294967295]
      //uint32_t mask = 100000000;
      //actually, LAMDA = lamda*INTERVAL_SUPERFRAME, i.e., every lamda superframe, one packet.
      uint16_t propa = (uint16_t)LAMDA_WIONE*NODE_NUM_WIONE;
      //if(propa == 4224) call Leds.led2Toggle();
      res = random%propa;//
      
      /*res = (uint16_t)random/propa * propa;
      if(res == random) res = 0;*/

      if(res == 0) return TRUE;
      else return FALSE;

  }

   uint8_t getSubslotPosWi1()  //for TC1, TC2 or TC3.
   {
      uint32_t res;
      uint16_t random = call Random.rand16(); //[0,4294967295]
      
      uint8_t propa = NUM_SUB_SLOT; //22;
      
      res = random%propa;//
      
      return res; //0 - 21

  }


   /*bool isAttemptPoisson(uint16_t lamda)  //for TC1, TC2 or TC3.
   {
      uint32_t res = call Random.rand32(); //[0,4294967295]
      uint32_t mask = 100000;
      uint16_t propa = NODE_NUM*lamda*SLOT_LEN; //e.g., 30*10*25 = 7500 λ, 25 > 22
      propa = (uint16_t)(100000.0/propa);//e.g., 100000.0/7500 = 13.3 = 13
      //debug
      //if(propa == 13) call Leds.led2Toggle(); //13 --- lamda = 10, 6 -- lamda = 20
      //else call Leds.led0Toggle();
    
      res = res%mask;//

      if(res<=propa) return TRUE;
      else return FALSE;

  }*/

  event void PMACSlot.sendDone(error_t packetErr, uint8_t type){

     atomic{
       isPushBusy = FALSE;
       //only TC2's retransmission is conducted in cc2420TransmitP.
       switch(type){
         /*case PMAC_TC_ONE_UMSG:
            isOnePushing = FALSE;
            wiOne.retries--;
            if(wiOne.retries == 0)
               wiOne.used=FALSE;
            break;
         case PMAC_TC_TWO_UMSG:
            isTwoPushing = FALSE;
            twoQueue[1].used=FALSE;
            //if(packetErr == SUCCESS)
            // call Leds.led2Toggle();
            break;*/
         case WIMAC_ONE:
	    //isThreePushing = FALSE;
            if(packetErr == SUCCESS)
		wiOne.used=FALSE;
	    else{
              //twoQueue[1].used=FALSE;
              //call Leds.led2Toggle();
	      wiOne.retries--;
	      if(wiOne.retries == 0)
                 wiOne.used=FALSE;
            }
            break;
         default:
            break;
       }
     }

  }

  //64slots per time sync cycle. 1st slot: time sync. 63rd slot: report 
  //32 slots per superframe, 1, 32(0) occupied ...
  uint8_t getSlotOffset(){
    uint8_t slotOffset = -1;
    switch(TOS_NODE_ID){
      case 2:
        slotOffset = 2;
        break;
      case 3:
        slotOffset = 3;
        break;
      case 4:
        slotOffset = 4;
        break;
      case 5:
        slotOffset = 5;
        break;
      case 6:
        slotOffset = 6;
        break;
      case 7:
        slotOffset = 7;
        break;
      case 8:
        slotOffset = 9;
        break;
      case 9:
        slotOffset = 10;
        break;
      case 10:
        slotOffset = 11;
        break;
      case 11:
        slotOffset = 12;
        break;
      case 12:
        slotOffset = 13;
        break;
      case 13:
        slotOffset = 14;
        break;
      case 14:
        slotOffset = 16;
        break;
      case 15:
        slotOffset = 17;
        break;
      case 16:
        slotOffset = 18;
        break;
      case 17:
        slotOffset = 19;
        break;
      case 18:
        slotOffset = 20;
        break;
      case 19:
        slotOffset = 21;
        break;
      case 20:
        slotOffset = 22;
        break;
      case 21:
        slotOffset = 23;
        break;
      //tc2, tc1 devices:
      case 22:
      case 23:
      case 24:
      case 25:
      case 26:
      case 27:
      case 28:
      case 29:
      case 30:
        slotOffset = 8;
        break;
      case 31:
        slotOffset = 15;
        break;
      default:
        break;

    }
    return slotOffset;

  }
  async event void PMACSlot.notifyHPISONE(){}
  
}
