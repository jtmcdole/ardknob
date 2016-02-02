// Copyright 2016 John McDole <john@mcdole.org>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef Encoder_h
#define Encoder_h

#include "Arduino.h"

class Encoder {
 public:
  Encoder(int a, int b);

  /* Returns -1 for CCW, 0 for no change, and 1 for CW */
  int poll();

 private:
  int _a, _b;
  unsigned long _buffer;
};

class PushButton {
  public:
    PushButton(int pin);
 
    /* Returns 1 for down, 0 for no change, and -1 for up */ 
    int poll();

  private:
    int _pin;
    int _state;
};

#endif
