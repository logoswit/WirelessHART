

interface PMACQueue {
   //async command message_t* getTDMAPacket(uint8_t sltoffset);
   //async command message_t* getCSMAPacket();
   //async command void sendTDMADone(message_t* msg, error_t error);
   //async command void sendCSMADone(message_t* msg, error_t error);
   async command message_t* getTimeSyncPkt();

   async command void abortPush();
   async command void readyPush(uint32_t abSltNum);

   //event void pktArrives(uint8_t type);
}
