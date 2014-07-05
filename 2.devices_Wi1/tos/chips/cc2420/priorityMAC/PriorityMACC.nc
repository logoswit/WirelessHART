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
 */

/**
 * PriorityMAC provides a prioity based hybrid MAC.
 *
 * This benefits ...
 *
 * @author Wei Shen (wei.shen@miun.se)
 * @email wei.shen@miun.se
 * @version: 1.0 $ $Date: 2009/08/20 01:37:44 $
 */

#include "CC2420.h"
#include "IEEE802154.h"
#include "prioritymac.h"

configuration PriorityMACC {
  provides interface Receive;
  provides interface SplitControl;
  provides interface Send as SendCSMA;
  provides interface PMACSlot;

  uses interface PMACQueue;
}

implementation {
  components MainC;

  //MainC.SoftwareInit -> TimeSyncC;
  //TimeSyncC.Boot -> MainC;

  components PriorityMACP as Pmac;
  SplitControl = Pmac;
  Receive = Pmac;
  PMACQueue = Pmac;
  SendCSMA = Pmac;
  PMACSlot = Pmac;
  //Pmac.Boot -> MainC;
  MainC.SoftwareInit -> Pmac;

  
  components CC2420ControlC;
  Pmac.Resource -> CC2420ControlC;
  Pmac.CC2420Power -> CC2420ControlC;

  components CC2420TransmitC;
  Pmac.SubControl -> CC2420TransmitC;
  Pmac.CC2420Transmit -> CC2420TransmitC;
  //Pmac.SubBackoff -> CC2420TransmitC;

  components CC2420ReceiveC;
  Pmac.SubReceive -> CC2420ReceiveC;
  Pmac.SubControl -> CC2420ReceiveC; // Pmac.SubControl -> CC2420TransmitC;

  components CC2420PacketC;
  Pmac.CC2420Packet -> CC2420PacketC;
  Pmac.CC2420PacketBody -> CC2420PacketC;
  Pmac.PacketTimeStamp32khz -> CC2420PacketC;

  components LedsC;

  Pmac.Leds -> LedsC;

  components RandomC;
  Pmac.Random -> RandomC;

  //components new TimerMilliC();
  //components new AlarmMicro16C() as AlarmMicro; //(TMicro);
  //Pmac.SlotAlarm -> AlarmMicro;

  //components new AlarmMicro16C() as CCAAlarmMicro; //(TMicro);
  //Pmac.CCAAlarm -> CCAAlarmMicro;

  //components LocalTimeMicroC as MicroTimerC;
  //Pmac.MicroTimer -> MicroTimerC;

  components new StateC();
  Pmac.SplitControlState -> StateC;

  Pmac.PacketTimeSyncOffset -> CC2420PacketC;


  components HplCC2420PinsC as Pins;
  Pmac.CCA -> Pins.CCA;

  components UserButtonC;
  //TestUserButtonC.Get -> UserButtonC;
  Pmac.Notify -> UserButtonC;

  components new Alarm32khz16C();
  Pmac.Alarm32k -> Alarm32khz16C;

  Pmac.CC2420Config -> CC2420ControlC;
  

}
