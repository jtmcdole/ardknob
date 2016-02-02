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

/* A simple rotary encoder library */
#include "RotaryEncoder.h"

Encoder::Encoder(int a, int b) {
  pinMode(a, INPUT_PULLUP);
  pinMode(b, INPUT_PULLUP);
  _a = a;
  _b = b;
}

int Encoder::poll() {
  unsigned int aa = digitalRead(_a) << 1 | digitalRead(_b);
  if (aa != (_buffer & 0x3)) {
    if (aa == 3) {
      // We're polling, so we can miss some of the pulses. Accept 2 or 3 pulse
      // readings, but not more or less.
      //     CCW:  100001, 1000, 1001
      //     CW: 010010, 0110, 0100
      // If we miss the 11 state, then there is no telling what we've recorded.
      aa = (_buffer == 0x21 || _buffer == 0x8 || _buffer == 0x9) ? -1 : 
	      (_buffer == 0x12 || _buffer == 0x6 || _buffer == 0x4) ? 1 : 0;
      _buffer = 3;
      return aa;
    }
    // Don't record the 11 in the string - it adds nothing.
    _buffer = _buffer == 3 ? aa : (_buffer << 2 | (aa & 0x3));
  }
  return 0;
}

PushButton::PushButton(int pin) {
  pinMode(pin, INPUT_PULLUP);
  _pin = pin;
  _state = -1;
}

int PushButton::poll() {
  unsigned int aa = digitalRead(_pin);
  if (aa != _state) {
    _state = aa;
    return aa ? -1 : 1;
  }
  return 0;  
}

