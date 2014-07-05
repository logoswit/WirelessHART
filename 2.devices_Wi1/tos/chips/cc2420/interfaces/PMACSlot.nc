

interface PMACSlot {
   async event void notifyHPISONE();
   async command error_t prolongTimer();
   async command error_t pushPacket(uint8_t type, uint8_t seqno, 
                                   uint32_t absltnum,uint8_t subslotPos);
   event void sendDone(error_t packetErr,uint8_t type);
}
