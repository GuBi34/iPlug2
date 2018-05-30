/*
 ==============================================================================
 
 This file is part of the iPlug 2 library
 
 Oli Larkin et al. 2018 - https://www.olilarkin.co.uk
 
 iPlug 2 is an open source library subject to commercial or open-source
 licensing.
 
 The code included in this file is provided under the terms of the WDL license
 - https://www.cockos.com/wdl/
 
 ==============================================================================
 */

#pragma once

/**
 * @file IPlug Open Sound Control (OSC) support - OSC message helpers
 * The code in this file is mostly copied from Cockos OSCII-BOT https://github.com/justinfrankel/oscii-bot
 * OSCII-BOT is licensed under the GPL, but this copy has been authorised for use under the WDL licence by Cockos Inc.
 *
 */

#define MAX_OSC_MSG_LEN 1024

static void OSC_BSWAPINTMEM(void *buf)
{
  char *p=(char *)buf;
  char tmp=p[0]; p[0]=p[3]; p[3]=tmp;
  tmp=p[1]; p[1]=p[2]; p[2]=tmp;
}

#define OSC_MAKEINTMEM4BE(x) OSC_BSWAPINTMEM(x)

// thanks, REAPER
class OscMessageWrite
{
public:
  OscMessageWrite();
  bool PushWord(const char* word);
  bool PushInt(int val); // push an int onto the message (not an int arg)
  bool PushIntArg(int val);
  bool PushFloatArg(float val);
  bool PushStringArg(const char* val);
  const char* GetBuffer(int* len);
  void DebugDump(const char* label, char* dump, int dumplen);
private:
  char m_msg[MAX_OSC_MSG_LEN];
  char m_types[MAX_OSC_MSG_LEN];
  char m_args[MAX_OSC_MSG_LEN];
  char* m_msg_ptr;
  char* m_type_ptr;
  char* m_arg_ptr;
};

class OscMessageRead
{
public:
  OscMessageRead(char* buf, int len); // writes over buf
  const char* GetMessage() const; // get the entire message string, no args
  int GetNumArgs() const;
  const char* PopWord();
  const void* GetIndexedArg(int idx, char* typeOut) const; // offset from popped args, NULL if failed. typeOut required
  const int* PopIntArg(bool peek);
  const float* PopFloatArg(bool peek);
  const char* PopStringArg(bool peek);
  void DebugDump(const char* label, char* dump, int dumplen);
private:
  char* m_msg_end;
  char* m_type_end;
  char* m_arg_end;
  char* m_msg_ptr;
  char* m_type_ptr;
  char* m_arg_ptr;
  bool m_msgok;
};

