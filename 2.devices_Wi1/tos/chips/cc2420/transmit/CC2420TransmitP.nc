/* 
 * Copyright (c) 2005-2006 Arch Rock Corporation 
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Arch Rock Corporation nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * ARCHED ROCK OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 */

/**
 * @author Jonathan Hui <jhui@archrock.com>
 * @author David Moss
 * @author Jung Il Choi Initial SACK implementation
 * @author JeongGil Ko
 * @author Razvan Musaloiu-E
 * @version $Revision: 1.18 $ $Date: 2010-04-13 20:27:05 $
 */

#include "CC2420.h"
#include "CC2420TimeSyncMessage.h"
#include "crc.h"
#include "message.h"

module CC2420TransmitP @safe() {

  provides interface Init;
  provides interface StdControl;
  provides interface CC2420Transmit as Send;
  //provides interface RadioBackoff;
  provides interface ReceiveIndicator as EnergyIndicator;
  provides interface ReceiveIndicator as ByteIndicator;
  
  uses interface Alarm<T32khz,uint32_t> as BackoffTimer;
  uses interface CC2420Packet;
  uses interface CC2420PacketBody;
  uses interface PacketTimeStamp<T32khz,uint32_t>;
  uses interface PacketTimeSyncOffset;
  uses interface GpioCapture as CaptureSFD;
  uses interface GeneralIO as CCA;
  uses interface GeneralIO as CSN;
  uses interface GeneralIO as SFD;

  uses interface Resource as SpiResource;
  uses interface ChipSpiResource;
  uses interface CC2420Fifo as TXFIFO;
  uses interface CC2420Ram as TXFIFO_RAM;
  uses interface CC2420Register as TXCTRL;
  uses interface CC2420Strobe as SNOP;
  uses interface CC2420Strobe as STXON;
  uses interface CC2420Strobe as STXONCCA;
  uses interface CC2420Strobe as SFLUSHTX;
  uses interface CC2420Register as MDMCTRL1;

  uses interface CC2420Strobe as STXENC;
  uses interface CC2420Register as SECCTRL0;
  uses interface CC2420Register as SECCTRL1;
  uses interface CC2420Ram as KEY0;
  uses interface CC2420Ram as KEY1;
  uses interface CC2420Ram as TXNONCE;

  uses interface CC2420Receive;
  uses interface Leds;
  uses interface Random;
  uses interface PMACSlot as PMACSlotTime;
}

implementation {

  /*typedef enum {
    S_STOPPED,
    S_STARTED,
    S_LOAD,
    S_SAMPLE_CCA,
    S_BEGIN_TRANSMIT,
    S_SFD,
    S_EFD,
    S_ACK_WAIT,
    S_CANCEL,
  } cc2420_transmit_state_t;*/
  typedef enum {
    S_STOPPED,
    S_STARTED,
    S_LOAD,
    S_SAMPLE_CCA,
    S_INDICATE_HPIS, //weishen
    S_BEGIN_TRANSMIT,
    S_BEGIN_TRANSMIT_INDICATE, //weishen
    S_TCTWO_HPIS_CCA, //weishen
    S_RELOAD_TRANSMIT,
    S_SFD,
    S_EFD,
    S_ACK_WAIT,
    S_CANCEL,
  } cc2420_transmit_state_t;

  enum{
   M_CCA_TC_TDMA,
   M_CCA_TC_ONE,
   M_CCA_TC_TWO,
  };

  // This specifies how many jiffies the stack should wait after a
  // TXACTIVE to receive an SFD interrupt before assuming something is
  // wrong and aborting the send. There seems to be a condition
  // on the micaZ where the SFD interrupt is never handled.
  enum {
    CC2420_ABORT_PERIOD = 15 //320 //weishen. in case still cannot capture SFD interrupt after this period.
  };

#ifdef CC2420_HW_SECURITY
  uint16_t startTime = 0;
  norace uint8_t secCtrlMode = 0;
  norace uint8_t nonceValue[16] = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01};
  norace uint8_t skip;
  norace uint16_t CTR_SECCTRL0, CTR_SECCTRL1;
  uint8_t securityChecked = 0;
  
  void securityCheck();
#endif
  
  norace message_t * ONE_NOK m_msg;
  
  norace uint8_t m_cca; 
  
  norace uint8_t m_tx_power;
  
  cc2420_transmit_state_t m_state = S_STOPPED;

  bool m_receiving = FALSE;
  
  uint16_t m_prev_time;
  
  /** Byte reception/transmission indicator */
  bool sfdHigh;
  
  /** Let the CC2420 driver keep a lock on the SPI while waiting for an ack */
  bool abortSpiRelease;
  
  /** Total CCA checks that showed no activity before the NoAck LPL send */
  norace int8_t totalCcaChecks;
  
  /** The initial backoff period */
  //norace uint16_t myInitialBackoff;
  
  /** The congestion backoff period */
  //norace uint16_t myCongestionBackoff;

    norace uint16_t boudaryHPIS;
    bool isSendingIndication;
  

  /***************** Prototypes ****************/
  error_t send( message_t * ONE p_msg);//, bool cca );
  error_t resend( bool cca );
  void loadTXFIFO();
  void attemptSend();
  void congestionBackoff();
  error_t acquireSpiResource();
  error_t releaseSpiResource();
  void signalDone( error_t err );
  
  void rewriteTXFIFOIndicate();
  void restoreTXFIFONormal();

  //--------------------csma-------------------------
  uint8_t m_BE;
  uint16_t backoffNum;
  uint16_t generateRandomBackoff(uint8_t BE);
  
  /***************** Init Commands *****************/
  command error_t Init.init() {
    call CCA.makeInput();
    call CSN.makeOutput();
    call SFD.makeInput();

    atomic isSendingIndication = FALSE;
    atomic m_cca = -1;
    return SUCCESS;
  }

  /***************** StdControl Commands ****************/
  command error_t StdControl.start() {
    atomic {
      call CaptureSFD.captureRisingEdge();
      m_state = S_STARTED;
      m_receiving = FALSE;
      abortSpiRelease = FALSE;
      m_tx_power = 0;
    }
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    atomic {
      m_state = S_STOPPED;
      call BackoffTimer.stop();
      call CaptureSFD.disable();
      call SpiResource.release();  // REMOVE
      call CSN.set();
    }
    return SUCCESS;
  }


  /**************** Send Commands ****************/
  async command error_t Send.send( message_t* ONE p_msg, bool useCca ) {
    uint8_t usecca;
    
    uint8_t type = (call CC2420PacketBody.getHeader( p_msg ))->type;
    //call Leds.led2Toggle();
    switch(type){
        case PMAC_TC_ONE_UMSG:
          usecca = M_CCA_TC_ONE;
          
          break;
        case PMAC_TC_TWO_UMSG:
          usecca = M_CCA_TC_TWO;
          break;
        case PMAC_TC_THREE_UMSG:
        case PMAC_TC_FOUR_UMSG:
        default://time sync, go , back, ...
          usecca = M_CCA_TC_TDMA;
          break;
    }
    atomic m_cca = usecca;
    return send( p_msg);
  }

  async command error_t Send.resend(bool useCca) {
    return resend( useCca );
  }

  async command error_t Send.cancel() {
    return SUCCESS;
  }

  async command error_t Send.modify( uint8_t offset, uint8_t* buf, 
                                     uint8_t len ) {
    return SUCCESS;
  }
  
  /***************** Indicator Commands ****************/
  command bool EnergyIndicator.isReceiving() {
    return !(call CCA.get());
  }
  
  command bool ByteIndicator.isReceiving() {
    bool high;
    atomic high = sfdHigh;
    return high;
  }
  
  /***************** PMACSlotTime ****************/
  /**
   * Must be called within a requestInitialBackoff event
   * @param backoffTime the amount of time in some unspecified units to backoff
   */
  async event void PMACSlotTime.notifyHPISONE() {
    atomic{
      switch(m_cca){
        case M_CCA_TC_ONE:
          //if m_state == sending indication, if send out, there is still time left, should
          //send another indication. NOT implement this time.
          if(m_state != S_SAMPLE_CCA)
       	     return;
          m_state = S_INDICATE_HPIS;
	  //call Leds.led2Toggle();
          call BackoffTimer.start(0);
          break;
        case M_CCA_TC_TWO:
          if(m_state != S_SAMPLE_CCA)
       	     return;
          if(backoffNum != 0){
             //call Leds.led2Toggle();
             m_state = S_TCTWO_HPIS_CCA; //S_INDICATE_HPIS;
             call BackoffTimer.start(CCA_SAMPLE_TIME);
          }
          break;
        case M_CCA_TC_TDMA: //nothing to do, TC3 and TC4 listen in HPIS has implemented in pmacp
          break;
        default:
          break;
      }
    }

    
  }

  /**
   * The CaptureSFD event is actually an interrupt from the capture pin
   * which is connected to timing circuitry and timer modules.  This
   * type of interrupt allows us to see what time (being some relative value)
   * the event occurred, and lets us accurately timestamp our packets.  This
   * allows higher levels in our system to synchronize with other nodes.
   *
   * Because the SFD events can occur so quickly, and the interrupts go
   * in both directions, we set up the interrupt but check the SFD pin to
   * determine if that interrupt condition has already been met - meaning,
   * we should fall through and continue executing code where that interrupt
   * would have picked up and executed had our microcontroller been fast enough.
   */
  uint16_t SFD_time,EFD_time;
  async event void CaptureSFD.captured( uint16_t timeSFD ) {
    
    uint8_t sfd_state = 0;
    atomic {
      //timeSFD = time;
      
      switch( m_state ) {
        
      case S_SFD:
        m_state = S_EFD;
        sfdHigh = TRUE;
        // in case we got stuck in the receive SFD interrupts, we can reset
        // the state here since we know that we are not receiving anymore
        m_receiving = FALSE;

        //for calculating accessDelay:
        //(call CC2420PacketBody.getMetadata( m_msg ))->timestamp = timeSFD;

        call CaptureSFD.captureFallingEdge();


        if (call PacketTimeSyncOffset.isSet(m_msg)) {
           //weishen, the first byte of the payload is 
           uint8_t absOffset = sizeof(cc2420_header_t);

           timesync16_t *timestamp = (timesync16_t *)((uint8_t*)m_msg+absOffset);

           *timestamp = timeSFD;

           call CSN.clr();
           call TXFIFO_RAM.write( absOffset, (uint8_t*)timestamp, sizeof(timesync16_t)  );
           call CSN.set();
        }

        if ( (call CC2420PacketBody.getHeader( m_msg ))->fcf & ( 1 << IEEE154_FCF_ACK_REQ ) ) {
          
          abortSpiRelease = TRUE;
        }
        //else This is an ack packet, don't release the chip's SPI bus lock because do not need ack.
      
        releaseSpiResource();
        call BackoffTimer.stop();

        if ( call SFD.get() ) {
          break;
        }
        /** Fall Through because the next interrupt was already received */

      case S_EFD:
        sfdHigh = FALSE;
        call CaptureSFD.captureRisingEdge();

        //EFD_time = time;

        //post printfTime();
        
        /*if ( (call CC2420PacketBody.getHeader( m_msg ))->fcf & ( 1 << IEEE154_FCF_ACK_REQ ) ) {
          m_state = S_ACK_WAIT;
          call BackoffTimer.start( CC2420_ACK_WAIT_DELAY );
        } else {
          signalDone(SUCCESS);
        }*/
        //for indication
        if(isSendingIndication){
           if(m_cca == M_CCA_TC_ONE){
              
              //isSendingIndication = FALSE;
              m_state = S_SAMPLE_CCA; //S_RELOAD_TRANSMIT;
              call BackoffTimer.start(CCA_SAMPLE_TIME);

              abortSpiRelease = FALSE;
              call ChipSpiResource.attemptRelease();
           }
           else if(m_cca == M_CCA_TC_TWO){ //
              m_state = S_RELOAD_TRANSMIT;
              call BackoffTimer.start(1);

              abortSpiRelease = FALSE; 
              call ChipSpiResource.attemptRelease();
           }
        }
        else{
           //weishen. ACK required or not.
           if ( (call CC2420PacketBody.getHeader(m_msg))->fcf & (1<<IEEE154_FCF_ACK_REQ)){
               m_state = S_ACK_WAIT;
               call BackoffTimer.start( CC2420_ACK_WAIT_DELAY); //128, 3.906ms.
           } else {
               signalDone(SUCCESS);
           }
        }
        
        if ( !call SFD.get() ) {
          break;
        }
        /** Fall Through because the next interrupt was already received */
        
      default:
        /* this is the SFD for received messages */
        if ( !m_receiving && sfdHigh == FALSE ) {
          sfdHigh = TRUE;
          call CaptureSFD.captureFallingEdge();
          // safe the SFD pin status for later use
          sfd_state = call SFD.get();
          //rcv_time_stamp:
          //if(timeSFD != 0)  //Weishen. 2012-10-29
          call CC2420Receive.sfd( timeSFD );
          m_receiving = TRUE;
          m_prev_time = timeSFD;
          if ( call SFD.get() ) {
            // wait for the next interrupt before moving on
            return;
          }
          // if SFD.get() = 0, then an other interrupt happened since we
          // reconfigured CaptureSFD! Fall through
        }
        
        if ( sfdHigh == TRUE ) {
          sfdHigh = FALSE;
          call CaptureSFD.captureRisingEdge();
          m_receiving = FALSE;
          /* if sfd_state is 1, then we fell through, but at the time of
           * saving the time stamp the SFD was still high. Thus, the timestamp
           * is valid.
           * if the sfd_state is 0, then either we fell through and SFD
           * was low while we safed the time stamp, or we didn't fall through.
           * Thus, we check for the time between the two interrupts.
           * FIXME: Why 10 tics? Seams like some magic number...
           */
          if ((sfd_state == 0) && (timeSFD - m_prev_time < 10) ) {
            call CC2420Receive.sfd_dropped();
            if (m_msg)
              call PacketTimeStamp.clear(m_msg);
          }
          break;
        }
      }
    }
  }

  /***************** ChipSpiResource Events ****************/
  async event void ChipSpiResource.releasing() {
    if(abortSpiRelease) {
      call ChipSpiResource.abortRelease();
    }
  }
  
  
  /***************** CC2420Receive Events ****************/
  /**
   * If the packet we just received was an ack that we were expecting,
   * our send is complete.
   */
  async event void CC2420Receive.receive( uint8_t type, message_t* ack_msg ) {
    cc2420_header_t* ack_header;
    cc2420_header_t* msg_header;
    cc2420_metadata_t* msg_metadata;
    uint8_t* ack_buf;
    uint8_t length;

    if ( type == IEEE154_TYPE_ACK && m_msg) {
      ack_header = call CC2420PacketBody.getHeader( ack_msg );
      msg_header = call CC2420PacketBody.getHeader( m_msg );
      
      if ( m_state == S_ACK_WAIT && msg_header->dsn == ack_header->dsn ) {
        call BackoffTimer.stop();
        
        msg_metadata = call CC2420PacketBody.getMetadata( m_msg );
        ack_buf = (uint8_t *) ack_header;
        length = ack_header->length;
        
        msg_metadata->ack = TRUE;
        msg_metadata->rssi = ack_buf[ length - 1 ];
        msg_metadata->lqi = ack_buf[ length ] & 0x7f;
        signalDone(SUCCESS);
      }
    }
  }

  /***************** SpiResource Events ****************/
  event void SpiResource.granted() {
    uint8_t cur_state;

    atomic {
      cur_state = m_state;
    }
    
    if(m_cca == M_CCA_TC_ONE){
       switch( cur_state ) {
          case S_LOAD:
             loadTXFIFO();
      	     break;
          case S_RELOAD_TRANSMIT:
             loadTXFIFO();
      	     break; 
	  case S_BEGIN_TRANSMIT:
             attemptSend();
      	     break; 
          case S_BEGIN_TRANSMIT_INDICATE:
             rewriteTXFIFOIndicate();
      	     break; 
	  case S_CANCEL:
      	    call CSN.clr();
      	    call SFLUSHTX.strobe();
      	    call CSN.set();
      	    releaseSpiResource();
      	    atomic m_state = S_STARTED;
      	    signal Send.sendDone( m_msg, ECANCEL );
      	    break;
    	  default:
      	    releaseSpiResource();
      	    break;
       }
    }
    else if(m_cca == M_CCA_TC_TWO){
       switch( cur_state ) {
          case S_LOAD:
             loadTXFIFO();
      	     break;
          case S_RELOAD_TRANSMIT:
             restoreTXFIFONormal();
      	     break; 
	  case S_BEGIN_TRANSMIT:
             attemptSend();
      	     break; 
          case S_BEGIN_TRANSMIT_INDICATE:
             rewriteTXFIFOIndicate();
      	     break; 
	  case S_CANCEL:
      	    call CSN.clr();
      	    call SFLUSHTX.strobe();
      	    call CSN.set();
      	    releaseSpiResource();
      	    atomic m_state = S_STARTED;
      	    signal Send.sendDone( m_msg, ECANCEL );
      	    break;
    	  default:
      	    releaseSpiResource();
      	    break;
       }
    }
    else{ //m_cca == M_CCA_TC_TDMA
       switch( cur_state ) {
          case S_LOAD:
             loadTXFIFO();
      	     break;
          //case S_RELOAD_TRANSMIT:
	  case S_BEGIN_TRANSMIT: //in fact, cannot come here. 
             attemptSend();
      	     break; 
          //case S_BEGIN_TRANSMIT_INDICATE: 
	  case S_CANCEL:
      	    call CSN.clr();
      	    call SFLUSHTX.strobe();
      	    call CSN.set();
      	    releaseSpiResource();
      	    atomic m_state = S_STARTED;
      	    signal Send.sendDone( m_msg, ECANCEL );
      	    break;
    	  default:
      	    releaseSpiResource();
      	    break;
       }
    }

  }
  
  /***************** TXFIFO Events ****************/
  /**
   * The TXFIFO is used to load packets into the transmit buffer on the
   * chip
   */
  async event void TXFIFO.writeDone( uint8_t* tx_buf, uint8_t tx_len,
                                     error_t error ) {

    uint8_t cur_state, cur_m_cca;
    bool cur_isSendingIndication; 
    atomic cur_state = m_state;
    atomic cur_isSendingIndication = isSendingIndication;
    atomic cur_m_cca = m_cca;

    call CSN.set();
    if ( cur_state == S_CANCEL ) {
      atomic {
        call CSN.clr();
        call SFLUSHTX.strobe();
        call CSN.set();
      }
      releaseSpiResource();
      m_state = S_STARTED;
      signal Send.sendDone( m_msg, ECANCEL );
      
    } else if (cur_m_cca == M_CCA_TC_TDMA ) { //TC_THREE, TC_FOUR, sync, go, back...
      atomic {
        m_state = S_BEGIN_TRANSMIT;
      }
      attemptSend();
      
    } 
    else if(cur_m_cca == M_CCA_TC_ONE ){
      
      if(cur_isSendingIndication){
         if(cur_state == S_BEGIN_TRANSMIT_INDICATE){ //strange,WriteFIFO_RAM may come here.
            //attemptSend();
            
         }
         else if(cur_state == S_RELOAD_TRANSMIT){ // after reload
            //call Leds.led2Toggle();
            
            atomic {
              isSendingIndication = FALSE;
              m_state = S_BEGIN_TRANSMIT;
            }
            attemptSend();
        }
      }
      else{ //first to load; 
         //releaseSpiResource(); //which is important. 
         atomic isSendingIndication = TRUE;
         //m_state = S_INDICATE_HPIS; //to modify and then start transmit indication.
         
         atomic m_state = S_BEGIN_TRANSMIT_INDICATE;
         //why modify? already be an invalid msg. after one month. maybe forget sth.
         //rewriteTXFIFOIndicate();
         attemptSend();
         //call BackoffTimer.start(0); 
      }
    }
    else if(cur_m_cca == M_CCA_TC_TWO){ //m_cca == M_CCA_TC_TWO
      if(cur_isSendingIndication){
         /*
         endTime = call BackoffTimer.getNow();
         if(endTime - startTime < 900) ;//call Leds.led2Toggle(); */
         //atomic m_state = S_BEGIN_TRANSMIT;
         //2012-07-20, I have used writeRAM to replace TXFIFO.write, so not come here.
         if(cur_state == S_BEGIN_TRANSMIT_INDICATE){
            attemptSend();
            call Leds.led0On();
            call Leds.led2On();
         }
         else if(cur_state == S_RELOAD_TRANSMIT){
            //after sending out an indication, continue backoff. 
            releaseSpiResource();
            atomic m_state = S_SAMPLE_CCA;
            call BackoffTimer.start(BACKOFF_UNIT);

            atomic isSendingIndication = FALSE;
        }
      }
      else{ //TC2, there are three chances to come writeDone, 1) after first load normal packet,
            //2) after load indication (isSendingIndication==TRUE), 
            //3) after reload normal (isSendingIndication==TRUE),.
         //This is the first load normal packet.
         releaseSpiResource();
         atomic {
           m_state = S_SAMPLE_CCA;
           m_BE =  PMAC_MINBE;
           backoffNum = generateRandomBackoff(m_BE); //20; for debug
           /*if(backoffNum == 0)
             call BackoffTimer.start(0);
           else
             call BackoffTimer.start(HPIS_TIME);*/
         }
         //signal RadioBackoff.requestInitialBackoff(m_msg);
         //backoffNum is at least 1.
         call BackoffTimer.start(BACKOFF_UNIT);
      }
    }
  }

  
  async event void TXFIFO.readDone( uint8_t* tx_buf, uint8_t tx_len, 
      error_t error ) {
  }
  
  
  /***************** Timer Events ****************/
  /**
   * The backoff timer is mainly used to wait for a moment before trying
   * to send a packet again. But we also use it to timeout the wait for
   * an acknowledgement, and timeout the wait for an SFD interrupt when
   * we should have gotten one.
   */
  async event void BackoffTimer.fired() {
    atomic{
       if(m_cca == M_CCA_TC_ONE){
          switch( m_state ) {
      	     case S_SAMPLE_CCA: 
        	if(call CCA.get()){ //cca pin goes high when channel is clear.
           	   //if(backoffNum != 0)
           	   //backoffNum--;
           	   //call Leds.led2Toggle();
           	   m_state = S_RELOAD_TRANSMIT; //reload and send it now. NO BREAK.
        	}
        	else{
            	   //no need to modifyFIFO again. NEED? NEED. 2012-07-21. 
                   //it was a bug took me one day.
                   //debug
           	   m_state = S_BEGIN_TRANSMIT_INDICATE;
           	   isSendingIndication = TRUE;
           	   if ( acquireSpiResource() == SUCCESS ) {
             		rewriteTXFIFOIndicate();
             	        //attemptSend();
           	   }
		   /*m_state = S_BEGIN_TRANSMIT_INDICATE;
		   isSendingIndication = TRUE;
		   if ( acquireSpiResource() == SUCCESS ) {
		        attemptSend();
		   } */ 
                   break;
                }
            case S_RELOAD_TRANSMIT:
        	//isSendingIndication = FALSE;
        	//call Leds.led1Toggle();
        	if ( acquireSpiResource() == SUCCESS ) { //which is important.
          	   loadTXFIFO();
          	   //restoreTXFIFONormal();
        	}
                break;
      	    case S_INDICATE_HPIS:
        	//transmit an indicating msg here.
        	//in case cannot get resource immediately. 
        	//So use HPIS_TIME instead of BACKOFF_UNIT is reasonable.
        	//call BackoffTimer.start(HPIS_TIME);
        	//if not transmitting, i.e.,S_BEGIN_TRANSMIT_INDICATE, send indication anyway.
        	m_state = S_BEGIN_TRANSMIT_INDICATE;

        	//rewriteTXFIFOIndicate();
        
		isSendingIndication = TRUE;
		if ( acquireSpiResource() == SUCCESS ) {
		     attemptSend();
		}        
        	//m_state = S_SAMPLE_CCA;
        	break;
      	    case S_BEGIN_TRANSMIT_INDICATE:  //in case cannot get resource immediately.
      	    case S_BEGIN_TRANSMIT:
      	    case S_CANCEL:
		/*if ( acquireSpiResource() == SUCCESS ) {
		  attemptSend();
		}*/
        	break;
        
      	    case S_ACK_WAIT:
		//weishen. In default, TinyOS uses isAck to check ACK or not in upper layer.
		//whatever ACK is rcved or not, signalDone(SUCCESS) here.
		//make a modification so as to enable retransmission here when transmit failure.
		//MAC retransmission save time to upload to upper layer and 
                //time to load packet again!
		//signalDone( SUCCESS );
		//We didn't receive ACK within ACK_WAIT time when there is a requirement of ACK.
		signalDone(FAIL);
		break;

      	    case S_SFD:
		// We didn't receive an SFD interrupt within CC2420_ABORT_PERIOD
		// jiffies. Assume something is wrong.
		call SFLUSHTX.strobe();
		call CaptureSFD.captureRisingEdge();
		releaseSpiResource();
		signalDone( ERETRY );
		break;
      	    default:
        	break;
      	 }//switch
       }//if
       else if(m_cca == M_CCA_TC_TWO){
         switch( m_state ) {
            case S_SAMPLE_CCA: 
                // sample CCA and wait a little longer if free, just in case we
		// sampled during the ack turn-around window
		//weishen. if TDMA, this will NOT happen!!!
		if(call CCA.get()){ //cca pin goes high when channel is clear.
		   //if(backoffNum != 0)
		   backoffNum--;
		}
		if ( backoffNum == 0 ) { //if ( call CCA.get() ) {
		  m_state = S_BEGIN_TRANSMIT;
		  //call BackoffTimer.start( CC2420_TIME_ACK_TURNAROUND *32); //7*32
		  //FOUND a BIG issue here:
		  if ( acquireSpiResource() == SUCCESS ) {
                     //notify PMAC to prolong the slot timer.
                     //call PMACSlotTime.prolongTimer();
		     attemptSend();
		  }
                  //signalDone(FAIL); //for test which part make pmac time sync inaccurary.
		  
		} else {
		  call BackoffTimer.start(BACKOFF_UNIT);
		}
                break;
            case S_TCTWO_HPIS_CCA:
                //Currently,when cross HPIS, backoffNum does not count down in 1st and/or 2nd!!!
           	if(!call CCA.get()){ //cca pin goes high when channel is clear.
              	   //channel is busy. TC1 is sending packet or indication or 
                   //TC2 packet is sending.
              	   //continue backoff
              	   m_state = S_SAMPLE_CCA;
              	   //call BackoffTimer.start(BACKOFF_UNIT);//BACKOFF_UNIT = 15 ticks in 32k.
                   call BackoffTimer.start(HPIS_TIME - CCA_SAMPLE_TIME);
                   //HPIS backoff only minus 1 not 2.
              	   break;
           	}
           	else{
              	   //send an indication then continue backoff.
              	   //no break 
                   //call Leds.led2Toggle();
              	   m_state = S_INDICATE_HPIS;
                   
           	}
            case S_INDICATE_HPIS:
		//transmit an indicating msg here.
		//in case cannot get resource immediately. 
		//So use HPIS_TIME instead of BACKOFF_UNIT is reasonable.
		//call BackoffTimer.start(HPIS_TIME); 
		//rewriteTXFIFOIndicate();
		m_state = S_BEGIN_TRANSMIT_INDICATE;
		isSendingIndication = TRUE;
		if ( acquireSpiResource() == SUCCESS ) {
		     rewriteTXFIFOIndicate();
		     //attemptSend();
		}
		
		//m_state = S_SAMPLE_CCA;
                break;
            case S_RELOAD_TRANSMIT:
                //isSendingIndication = FALSE;
		//call Leds.led2Toggle();
		if ( acquireSpiResource() == SUCCESS ) { //which is important.
		  //loadTXFIFO();
		  restoreTXFIFONormal();
		}
                break;
            case S_BEGIN_TRANSMIT_INDICATE:  //in case cannot get resource immediately.
            case S_BEGIN_TRANSMIT:
            case S_CANCEL:
        	break;
            case S_ACK_WAIT:
                //weishen. In default, TinyOS uses isAck to check ACK or not in upper layer.
		//whatever ACK is rcved or not, signalDone(SUCCESS) here.
		//make a modification so as to enable retransmission here when transmit failure.
		//MAC retransmission save time to upload to upper layer and time to 
                //load packet again!
		//signalDone( SUCCESS );
		//We didn't receive ACK within ACK_WAIT time when there is a requirement of ACK.
		atomic{
		   m_BE++;
		   if(m_BE <= PMAC_MAXBE){
		     backoffNum = generateRandomBackoff(m_BE);
		     call BackoffTimer.start(BACKOFF_UNIT); 
		   }
		   else
		     signalDone(FAIL);
		}
                break;
            case S_SFD:
                // We didn't receive an SFD interrupt within CC2420_ABORT_PERIOD
        	// jiffies. Assume something is wrong.
        	call SFLUSHTX.strobe();
		call CaptureSFD.captureRisingEdge();
		releaseSpiResource();
		signalDone( ERETRY );
        	break;
            //case S_BEGIN_TRANSMIT_INDICATE:
            //;//call Leds.led2Toggle();
            default:
                break;
         }
       }
       else{ //m_cca == M_CCA_TC_THREE and FOUR, m_cca == M_CCA_TC_TDMA
          //attemptSend(); is invoked in write Done. CCASample is implemented in Pmac.
         switch( m_state ) {
            case S_ACK_WAIT://only when ACK is required and ACK is not rcved during ...
               signalDone(FAIL);
               break;
            case S_SFD:
               // We didn't receive an SFD interrupt within CC2420_ABORT_PERIOD
	       // jiffies. Assume something is wrong.
		call SFLUSHTX.strobe();
		call CaptureSFD.captureRisingEdge();
		releaseSpiResource();
		signalDone( ERETRY );
		break;

      	    default:
        	break;

         }
       }

    }
  }
      
  /***************** Functions ****************/
  /**
   * Set up a message to be sent. First load it into the outbound tx buffer
   * on the chip, then attempt to send it.
   * @param *p_msg Pointer to the message that needs to be sent
   * @param cca TRUE if this transmit should use clear channel assessment
   */
  error_t send( message_t* ONE p_msg){ //, uint8_t cca ) {
    atomic {
      if (m_state == S_CANCEL) {
        return ECANCEL;
      }
      
      if ( m_state != S_STARTED ) {
        return FAIL;
      }
      
#ifdef CC2420_HW_SECURITY
      securityChecked = 0;
#endif
      m_state = S_LOAD;
      //m_cca = cca;
      m_msg = p_msg;
      totalCcaChecks = 0;
      isSendingIndication = FALSE;
      backoffNum = 0;
    }
    
    if ( acquireSpiResource() == SUCCESS ) {
      loadTXFIFO();
    }

    return SUCCESS;
  }
  
  /**
   * Resend a packet that already exists in the outbound tx buffer on the
   * chip
   * @param cca TRUE if this transmit should use clear channel assessment
   */
  error_t resend( bool cca ) {
    
    return SUCCESS;
  }
#ifdef CC2420_HW_SECURITY

  task void waitTask(){
    call Leds.led2Toggle();
    if(SECURITYLOCK == 1){
      post waitTask();
    }else{
      securityCheck();
    }
  }

  void securityCheck(){

    cc2420_header_t* msg_header;
    cc2420_status_t status;
    security_header_t* secHdr;
    uint8_t mode;
    uint8_t key;
    uint8_t micLength;

    msg_header = (cc2420_header_t*)m_msg->header;

    if(!(msg_header->fcf & (1 << IEEE154_FCF_SECURITY_ENABLED))){
      // Security is not used for this packet
      // Make sure to set mode to 0 and the others to the default values
      CTR_SECCTRL0 = ((0 << CC2420_SECCTRL0_SEC_MODE) |
		      (1 << CC2420_SECCTRL0_SEC_M) |
		      (1 << CC2420_SECCTRL0_SEC_TXKEYSEL) |
		      (1 << CC2420_SECCTRL0_SEC_CBC_HEAD)) ;
      
      call CSN.clr();
      call SECCTRL0.write(CTR_SECCTRL0);
      call CSN.set();

      return;
    }

    if(SECURITYLOCK == 1){
      post waitTask();
    }else {
      //Will perform encryption lock registers
      atomic SECURITYLOCK = 1;

      secHdr = (security_header_t*) &msg_header->secHdr;
#if ! defined(TFRAMES_ENABLED)
    secHdr=(security_header_t*)((uint8_t*)secHdr+1);
#endif

      memcpy(&nonceValue[3], &(secHdr->frameCounter), 4);

      skip = secHdr->reserved;
      key = secHdr->keyID[0]; // For now this is the only key selection mode.

      if (secHdr->secLevel == NO_SEC){
	mode = CC2420_NO_SEC;
	micLength = 4;
      }else if (secHdr->secLevel == CBC_MAC_4){
	//	call Leds.led0Toggle();
	mode = CC2420_CBC_MAC;
	micLength = 4;
      }else if (secHdr->secLevel == CBC_MAC_8){
	mode = CC2420_CBC_MAC;
	micLength = 8;
      }else if (secHdr->secLevel == CBC_MAC_16){
	mode = CC2420_CBC_MAC;
	micLength = 16;
      }else if (secHdr->secLevel == CTR){
	//	call Leds.led1Toggle();
	mode = CC2420_CTR;
	micLength = 4;
      }else if (secHdr->secLevel == CCM_4){
	mode = CC2420_CCM;
	micLength = 4;
      }else if (secHdr->secLevel == CCM_8){
	mode = CC2420_CCM;
	micLength = 8;
      }else if (secHdr->secLevel == CCM_16){
	mode = CC2420_CCM;
	micLength = 16;
      }else{
	return;
      }
      
      CTR_SECCTRL0 = ((mode << CC2420_SECCTRL0_SEC_MODE) |
		      ((micLength-2)/2 << CC2420_SECCTRL0_SEC_M) |
		      (key << CC2420_SECCTRL0_SEC_TXKEYSEL) |
		      (1 << CC2420_SECCTRL0_SEC_CBC_HEAD)) ;
#ifndef TFRAMES_ENABLED
      CTR_SECCTRL1 = (skip+11+sizeof(security_header_t)+((skip+11+sizeof(security_header_t))<<8));
#else
      CTR_SECCTRL1 = (skip+10+sizeof(security_header_t)+((skip+10+sizeof(security_header_t))<<8));
#endif

      call CSN.clr();
      call SECCTRL0.write(CTR_SECCTRL0);
      call CSN.set();

      call CSN.clr();
      call SECCTRL1.write(CTR_SECCTRL1);
      call CSN.set();

      call CSN.clr();
      call TXNONCE.write(0, nonceValue, 16);
      call CSN.set();

      call CSN.clr();
      status = call SNOP.strobe();
      call CSN.set();

      while(status & CC2420_STATUS_ENC_BUSY){
	call CSN.clr();
	status = call SNOP.strobe();
	call CSN.set();
      }
      
      // Inline security will be activated by STXON or STXONCCA strobes

      atomic SECURITYLOCK = 0;

    }
  }
#endif

  /**
   * Attempt to send the packet we have loaded into the tx buffer on 
   * the radio chip.  The STXONCCA will send the packet immediately if
   * the channel is clear.  If we're not concerned about whether or not
   * the channel is clear (i.e. m_cca == FALSE), then STXON will send the
   * packet without checking for a clear channel.
   *
   * If the packet didn't get sent, then congestion == TRUE.  In that case,
   * we reset the backoff timer and try again in a moment.
   *
   * If the packet got sent, we should expect an SFD interrupt to take
   * over, signifying the packet is getting sent.
   * 
   * If security is enabled, STXONCCA or STXON will perform inline security
   * options before transmitting the packet.
   */
  void attemptSend() {
    atomic {
      /*if (m_state == S_CANCEL) {
        call SFLUSHTX.strobe();
        releaseSpiResource();
        call CSN.set();
        m_state = S_STARTED;
        signal Send.sendDone( m_msg, ECANCEL );
        return;
      }*/
#ifdef CC2420_HW_SECURITY
      if(securityChecked != 1){
	securityCheck();
      }
      securityChecked = 1;
#endif

      call CSN.clr();
      call STXON.strobe();
      m_state = S_SFD;
      call CSN.set();
    }
 
    call BackoffTimer.start(CC2420_ABORT_PERIOD);
    
  }
  
  
  /**  
   * Congestion Backoff
   */
  void congestionBackoff() {
    atomic {
      //signal RadioBackoff.requestCongestionBackoff(m_msg);
      //call BackoffTimer.start(myCongestionBackoff);
    }
  }
  
  error_t acquireSpiResource() {
    error_t error = call SpiResource.immediateRequest();
    if ( error != SUCCESS ) {
      call SpiResource.request();
    }
    return error;
  }

  error_t releaseSpiResource() {
    call SpiResource.release();
    return SUCCESS;
  }


  /** 
   * Setup the packet transmission power and load the tx fifo buffer on
   * the chip with our outbound packet.  
   *
   * Warning: the tx_power metadata might not be initialized and
   * could be a value other than 0 on boot.  Verification is needed here
   * to make sure the value won't overstep its bounds in the TXCTRL register
   * and is transmitting at max power by default.
   *
   * It should be possible to manually calculate the packet's CRC here and
   * tack it onto the end of the header + payload when loading into the TXFIFO,
   * so the continuous modulation low power listening strategy will continually
   * deliver valid packets.  This would increase receive reliability for
   * mobile nodes and lossy connections.  The crcByte() function should use
   * the same CRC polynomial as the CC2420's AUTOCRC functionality.
   */
  void loadTXFIFO() {
    cc2420_header_t* header = call CC2420PacketBody.getHeader( m_msg );
    uint8_t tx_power = (call CC2420PacketBody.getMetadata( m_msg ))->tx_power;
    uint8_t cur_state;

    if ( !tx_power ) {
      tx_power = CC2420_DEF_RFPOWER;
    }
    
    call CSN.clr();
    
    if ( m_tx_power != tx_power ) {
      call TXCTRL.write( ( 2 << CC2420_TXCTRL_TXMIXBUF_CUR ) |
                         ( 3 << CC2420_TXCTRL_PA_CURRENT ) |
                         ( 1 << CC2420_TXCTRL_RESERVED ) |
                         ( (tx_power & 0x1F) << CC2420_TXCTRL_PA_LEVEL ) );
    }
    
    m_tx_power = tx_power;
    
    atomic cur_state = m_state;
    if(m_cca == M_CCA_TC_ONE && (cur_state != S_RELOAD_TRANSMIT)){
      //uint8_t tmpLen __DEPUTY_UNUSED__ = header->length - 1;
      uint8_t invalidMsg[2];
      invalidMsg[0] = 1;
      invalidMsg[1] = 0x07;
      call TXFIFO.write((uint8_t *)invalidMsg, 2);

     
    }
    else
    {
      uint8_t tmpLen __DEPUTY_UNUSED__ = header->length - 1;
      call TXFIFO.write(TCAST(uint8_t * COUNT(tmpLen), header), header->length - 1);
    }
  }

  //This is only for TC2, when crosses HPIS and be in backoff, send an indicate after busy CCA.
 // here can use WriteRAM replaces TXFIFO.write, the former takes 648 microticks from
 // start send to SED. the latter takes 2040 microticks.
  void rewriteTXFIFOIndicate(){

      uint8_t cur_state; 

      /*uint8_t invalidMsg[2];
      invalidMsg[0] = 1;
      invalidMsg[1] = 0x07;
      call CSN.clr();
      call TXFIFO.write((uint8_t *)invalidMsg,2);*/

      uint8_t invalidMsg[1];
      invalidMsg[0] = 1;

      call CSN.clr();
      call TXFIFO_RAM.write( 0, (uint8_t*)invalidMsg, 1 );
      call CSN.set();

      atomic cur_state= m_state;
      if(cur_state != S_BEGIN_TRANSMIT_INDICATE){
            call Leds.led0On();
            call Leds.led2On();
      }
      
      attemptSend();
  }
  void restoreTXFIFONormal(){ // for TC1 TC2.
    cc2420_header_t* header = call CC2420PacketBody.getHeader( m_msg );
    uint8_t tmpLen __DEPUTY_UNUSED__ = header->length - 1;

    //call Leds.led2Toggle();

    call CSN.clr();
    call TXFIFO.write(TCAST(uint8_t * COUNT(tmpLen), header), header->length - 1);
  }
  
  void signalDone( error_t err ) {
    atomic m_state = S_STARTED;
    abortSpiRelease = FALSE;
    call ChipSpiResource.attemptRelease();
    //reset m_cca:
    m_cca = -1;
    signal Send.sendDone( m_msg, err );
  }

  uint16_t generateRandomBackoff(uint8_t BE)  //refer. tkn154 CapP.nc
  {
     // return random number from [0,(2^BE) - 1] (uniform distr.)
     //return random number from [1,(2^BE)] (uniform distr.)
    uint16_t res = call Random.rand16();
    uint16_t mask = 0xFFFF;
    mask <<= BE;
    mask = ~mask; //if BE = 3, mask = 0x111 = 7
    mask += 1; //weishen, mask = 8
    res = res%mask;//weishen, res = 0 - 7
    res += 1; //res = 1 - 8
    //res &= mask;
    return res;
  }

  event void PMACSlotTime.sendDone(error_t packetErr,uint8_t type){}
}

