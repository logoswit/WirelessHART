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

#include "CC2420.h"
#include "IEEE802154.h"
#include "Testcc2420Radio.h"

configuration Testcc2420RadioC {
}

implementation {
  components MainC;

  components Testcc2420RadioP as TestRadio;
  TestRadio.Boot -> MainC;

  /*components CC2420ActiveMessageC as AM;
  TestRadio.SplitControl -> AM;
  TestRadio.Receive -> AM.Receive[10];*/
  components ActiveMessageC;
  TestRadio.RadioControl -> ActiveMessageC;
  //TestRadio.PMACSlotTime -> ActiveMessageC;

  //PMAC_TC_ONE_UMSG can be TC1 or TC2.
  components new AMSenderC(PMAC_TC_ONE_UMSG) as SendTC;
  components new AMReceiverC(PMAC_TC_ONE_UMSG) as ReceiveTC;

  //components new AMSenderC(PMAC_TC_TWO_UMSG) as SendTCTwo;
  //components new AMReceiverC(PMAC_TC_TWO_UMSG) as ReceiveTCTwo;

  TestRadio.AMSendTC -> SendTC;
  TestRadio.ReceiveTC -> ReceiveTC;
  //TestRadio.SubPacket -> SendControl;
  //TestRadio.SubAMPacket -> SendControl;
  //components new TimerMilliC();
  //TestRadio.Timer -> TimerMilliC;
   
  components LedsC;
  TestRadio.Leds -> LedsC;
  
  components SerialPrintfC;  //for printf.

}
