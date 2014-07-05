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

module Testcc2420RadioP @safe() {

  uses interface SplitControl as RadioControl;

  uses interface Boot;
  uses interface Receive as ReceiveTC;
  uses interface AMSend as AMSendTC;
  //uses interface Timer<TMilli>;
  //uses interface Alarm<TMicro,uint16_t> as PoissonAlarm;
  uses interface Leds;
  //uses interface PMACSlotTime;
  //uses interface Random;

}

implementation {
  message_t sndMsg;
  task void startRadio();
  task void stopRadio();


  /***************** SplitControl Commands ****************/
  event void Boot.booted() {
 
     post startRadio();   
     
  }

  /***************** SplitControl Events ***************/
  event void RadioControl.startDone(error_t error) {
    if(!error) {
      
    }
    
  }

    
  event void RadioControl.stopDone(error_t error) {
    
  }

  event message_t *ReceiveTC.receive(message_t* msg, void* payload, 
      uint8_t len) {

   return msg;
  }

  event void AMSendTC.sendDone(message_t* msg, error_t error) {
    //call Leds.led0Toggle();
    if(error == SUCCESS)
         call Leds.led1Toggle();
    else if(error == FAIL){
         call Leds.led0Toggle();
    }
    else if(error == EALREADY){
         //call Leds.led2Toggle();
    }
    else if(error == EBUSY){
         //call Leds.led1Toggle();
    }

    //atomic sendCSMABusy = FALSE;
  }

  task void startRadio() {
    if(call RadioControl.start() != SUCCESS) {
      post startRadio();
    }
  }

  task void stopRadio() {
    if(call RadioControl.stop() != SUCCESS) {
        post stopRadio();
    }
  }

  
 
}
