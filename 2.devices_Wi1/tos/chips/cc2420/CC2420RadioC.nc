/*
 * "Copyright (c) 2005 Stanford University. All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and
 * its documentation for any purpose, without fee, and without written
 * agreement is hereby granted, provided that the above copyright
 * notice, the following two paragraphs and the author appear in all
 * copies of this software.
 * 
 * IN NO EVENT SHALL STANFORD UNIVERSITY BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
 * ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN
 * IF STANFORD UNIVERSITY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 * 
 * STANFORD UNIVERSITY SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE
 * PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND STANFORD UNIVERSITY
 * HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
 * ENHANCEMENTS, OR MODIFICATIONS."
 */

/**
 * Radio wiring for the CC2420.  This layer seperates the common
 * wiring of the lower-layer components of the CC2420 stack and makes
 * them available to clients like the AM stack and the IEEE802.15.4
 * stack.
 *
 * This component provides the highest-level internal interface to
 * other components of the CC2420 stack.
 *
 * @author Philip Levis
 * @author David Moss
 * @author Stephen Dawson-Haggerty
 * @version $Revision: 1.2 $ $Date: 2009/08/20 01:37:44 $
 */

#include "CC2420.h"

configuration CC2420RadioC {
  provides {
    interface SplitControl;

    interface Resource[uint8_t clientId];
    interface Send as BareSend;
    interface Receive as BareReceive;
    interface Packet as BarePacket;

    interface Send    as ActiveSend;
    interface Receive as ActiveReceive;

    interface CC2420Packet;
    interface PacketAcknowledgements;
    interface LinkPacketMetadata;
    //interface PMACSlotTime;
   // interface LowPowerListening;
   // interface PacketLink;

  }
}
implementation {

  components PriorityMACC as PMACC;
  components UniqueSendC;
  components UniqueReceiveC;
  components CC2420TinyosNetworkC;
  components CC2420PacketC;
  components CC2420ControlC;
  
  
  //PacketLink = LinkC;
 // LowPowerListening = LplC;
  CC2420Packet = CC2420PacketC;
  PacketAcknowledgements = CC2420PacketC;
  LinkPacketMetadata = CC2420PacketC;
  
  Resource = CC2420TinyosNetworkC;
  BareSend = CC2420TinyosNetworkC.Send;
  BareReceive = CC2420TinyosNetworkC.Receive;
  BarePacket = CC2420TinyosNetworkC.BarePacket;
  
  ActiveSend = CC2420TinyosNetworkC.ActiveSend;
  ActiveReceive = CC2420TinyosNetworkC.ActiveReceive;

  // SplitControl Layers
  //SplitControl = LplC;
  //LplC.SubControl -> CsmaC;
  SplitControl = PMACC;
  //PMACSlotTime = PMACC;
  
  // Send Layers
  CC2420TinyosNetworkC.SubSend -> UniqueSendC;
  //UniqueSendC.SubSend -> PMACC;  //Add this later. Use SMAC in setup period.
  components PriorityMACQueueP;
  UniqueSendC.SubSend -> PriorityMACQueueP;

  PriorityMACQueueP.CC2420PacketBody -> CC2420PacketC;
  PriorityMACQueueP.PacketAcknowledgements -> CC2420PacketC;
  PriorityMACQueueP.PMACSlot -> PMACC;
  //PriorityMACQueueP.SendCSMA -> PMACC;

  components LedsC;
  PriorityMACQueueP.Leds -> LedsC;

  components new Alarm32khz16C();
  PriorityMACQueueP.SubSlotAlarm32k -> Alarm32khz16C;

  components RandomC;
  PriorityMACQueueP.Random -> RandomC;

  //LinkC.SubSend -> LplC.Send;
  //LplC.SubSend -> CsmaC;
  
  // Receive Layers
  CC2420TinyosNetworkC.SubReceive -> UniqueReceiveC.Receive;
  //LplC.SubReceive -> UniqueReceiveC.Receive;
  UniqueReceiveC.SubReceive ->  PMACC.Receive;

  //components PriorityMACQueueP;
  PMACC.PMACQueue -> PriorityMACQueueP;
  
  
}
