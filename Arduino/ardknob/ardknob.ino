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

#include <RotaryEncoder.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <avr/pgmspace.h>

#include "icon.h"

#define OLED_RESET 4
Adafruit_SSD1306 display(OLED_RESET);

Encoder encs[] = {
  Encoder(2, 3),
  Encoder(5, 6),
  Encoder(8, 9),
};
const int encsl = sizeof(encs) / sizeof(Encoder);

PushButton buts[] = {
  PushButton(4),
  PushButton(7),
  PushButton(10),
};
const int butsl = sizeof(buts) / sizeof(PushButton);


void setup() {
  //Serial.begin(57600);
  Serial.begin(115200);
  // wait for serial port to connect. Needed for native USB port only
  while (!Serial);
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.setTextSize(2);
  display.setTextColor(WHITE, BLACK);
  display.setCursor(0, 0);
  display.drawXBitmap(0, 0, codefu_bits, codefu_width, codefu_height, WHITE);
  display.display();
  delay(3000);
  display.clearDisplay();
  display.display();
}

unsigned int buff2s(byte* buf) {
  return buf[0] << 8 | buf[1];
}

void drawXBitmap(int16_t x, int16_t y, uint8_t *bitmap, int16_t w, int16_t h, uint16_t color) {
  int16_t i, j, byteWidth = (w + 7) / 8;
  uint8_t byte;
  for (j = 0; j < h; j++) {
    for (i = 0; i < w; i++ ) {
      if (i & 7) byte >>= 1;
      else       byte   = bitmap[j * byteWidth + i / 8];
      if (byte & 0x01) display.drawPixel(x + i, y + j, color);
    }
  }
}

void drawXBitmap(int16_t x, int16_t y, uint8_t *bitmap, int16_t w, int16_t h, uint16_t color, uint16_t bg) {
  int16_t i, j, byteWidth = (w + 7) / 8;
  uint8_t byte;
  for (j = 0; j < h; j++) {
    for (i = 0; i < w; i++ ) {
      if (i & 7) byte >>= 1;
      else       byte   = bitmap[j * byteWidth + i / 8];
      display.drawPixel(x + i, y + j, (byte & 0x01) ? color : bg);
    }
  }
}

bool handleCommand(byte cmd, unsigned int size, byte * buff) {
  switch (cmd) {
    case 0:
      display.display();
      break;
    case 1:
      if (size == 0) display.clearDisplay();
      else if (size == 2) display.fillScreen(buff2s(buff));
      break;
    case 2:
      if (size != 4) break;
      display.setCursor(buff2s(buff), buff2s(buff + 2));
      break;
    case 3:
      if (size != 2) break;
      display.setTextSize(buff2s(buff));
      break;
    case 4:
      if (size == 2) display.setTextColor(buff2s(buff));
      else if (size == 4) display.setTextColor(buff2s(buff), buff2s(buff + 2));
      break;
    case 5:
      // TEXT
      for (int i = 0; i < size; i++) display.write(buff[i]);
      break;
    case 6:
      if (size != 10) break;
      display.drawLine(
        buff2s(buff),
        buff2s(buff + 2),
        buff2s(buff + 4),
        buff2s(buff + 6),
        buff2s(buff + 8));
      break;
    case 7:
      if (size != 14) break;
      display.drawTriangle(
        buff2s(buff), // x0
        buff2s(buff + 2), // y0
        buff2s(buff + 4), // x1
        buff2s(buff + 6), // y1
        buff2s(buff + 8), // x2
        buff2s(buff + 10), // y2
        buff2s(buff + 12) // color
      );
      break;
    case 8:
      if (size != 14) break;
      display.fillTriangle(
        buff2s(buff), // x0
        buff2s(buff + 2), // y0
        buff2s(buff + 4), // x1
        buff2s(buff + 6), // y1
        buff2s(buff + 8), // x3
        buff2s(buff + 10), // y3
        buff2s(buff + 12) // color
      );
      break;
    case 9:
      if (size  != 10) break;
      display.drawRect(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // w
        buff2s(buff + 6), // h
        buff2s(buff + 8) // color
      );
      break;
    case 10:
      if (size  != 10) break;
      display.fillRect(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // w
        buff2s(buff + 6), // h
        buff2s(buff + 8) // color
      );
      break;
    case 11:
      if (size  != 12) break;
      display.drawRoundRect(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // w
        buff2s(buff + 6), // h
        buff2s(buff + 8), // radius
        buff2s(buff + 10) // color
      );
      break;
    case 12:
      if (size  != 12) break;
      display.fillRoundRect(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // w
        buff2s(buff + 6), // h
        buff2s(buff + 8), // radius
        buff2s(buff + 10) // color
      );
      break;
    case 13:
      if (size  != 8) break;
      display.drawCircle(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // r
        buff2s(buff + 6) // color
      );
      break;
    case 14:
      if (size  != 8) break;
      display.fillCircle(
        buff2s(buff), // x
        buff2s(buff + 2), // y
        buff2s(buff + 4), // r
        buff2s(buff + 6) // color
      );
      break;
    case 15:
      if (size < 10) break;
      display.drawBitmap(
        buff2s(buff),      // x
        buff2s(buff + 2),  // y
        buff + 10,         // 1-bit bitmap
        buff2s(buff + 4),  // w
        buff2s(buff + 6),  // h
        buff2s(buff + 8)); // fgc
      break;
    case 16:
      if (size < 12) break;
      display.drawBitmap(
        buff2s(buff),       // x
        buff2s(buff + 2),   // y
        buff + 12,          // 1-bit bitmap
        buff2s(buff + 4),   // w
        buff2s(buff + 6),   // h
        buff2s(buff + 8),   // fgc
        buff2s(buff + 10)); // bgc
      break;
    case 17:
      if (size < 10) break;
      drawXBitmap(
        buff2s(buff),      // x
        buff2s(buff + 2),  // y
        buff + 10,         // 1-bit bitmap
        buff2s(buff + 4),  // w
        buff2s(buff + 6),  // h
        buff2s(buff + 8)); // fgc
      break;
    case 18:
      if (size < 12) break;
      drawXBitmap(
        buff2s(buff),       // x
        buff2s(buff + 2),   // y
        buff + 12,          // 1-bit bitmap
        buff2s(buff + 4),   // w
        buff2s(buff + 6),   // h
        buff2s(buff + 8),   // fgc
        buff2s(buff + 10)); // bgc
      break;
    case 19:
      // RESERVED: Encoder rotation or button press
      // Basically not sure how I'm going to do this, but it should never be sent to us,
      // and thus never expected in return.
      return false;
      break;
    default:
      return false;
  }
  return true;
}

int fletcher16(byte* data, int length) {
  int sum1 = 0xB5, sum2 = 0xC3;
  int i;
  for (i = 0; i < length; i++) {
    sum1 = (sum1 + data[i]) % 255;
    sum2 = (sum2 + sum1) % 255;
  }
  return ((sum2 & 0xFF) << 8) | (sum1 & 0xFF);
}

byte buff[128] = {0};
int buffo = 0;
unsigned long buff_start = 0;
bool drain = false;

void _drainSerial() {
  drain = true;
  int avail = Serial.available();
  if (avail) {
    Serial.readBytes(buff, Serial.available());
    buff_start = millis(); // RESET TIMER
    buffo = 0;
  }
}

/*
   Commands are binary:
     8 bits: size (including size and command)
     8 bits: user defined ACK that will be passed back with command
     8 bits: command (CMD)
     X-5 bytes: arguments
     16 bits: fletcher16 checksum

   Normal operations:
       Respond with 2 bytes: ACK + CMD
   Error handling:
       Checksum fails
       Overflow (Size > 128)
       Buffer underflow (command not completed after 100ms):
       -> Report Error CMD 0xFF and ACK:
           -> 0xFF checksum
           -> 0xFE overflow
           -> 0xFD underflow
       -> Drain serial
       -> Caller waits 100ms before re-establishing comms,
          this 100ms timer will reset with every byte receieved.

       Command not recognized (sum succeeds)
       -> Do not execute
       -> Report CMD 0xFF ACK 0xFC
       -> Continue processing
*/
void readSerial() {
  int elapsed = millis() - buff_start;
  if (elapsed > 100) {
    if (drain) drain = false;
    else if (buffo) {
      // Warning: underflow
      buff[0] = 0xFD;
      buff[1] = 0xFF;
      Serial.write(buff, 2);
      _drainSerial();
      return;
    }
  }
  if (drain) {
    _drainSerial();
    return;
  }
  while (Serial.available() > 0) {
    byte read = Serial.read();
    buff[buffo++] = read;
    if (buffo == 1) {
      buff_start = millis();
      if (read > sizeof(buff)) {
        buff[0] = read;
        buff[1] = 0xFF;
        Serial.write(buff, 2);
        _drainSerial();
        return;
      }
    }
    if (buff[0] == buffo) {
      // Test the checksum
      if (fletcher16(buff, buffo)) {
        buff[0] = buff[1] = 0xFF;
        Serial.write(buff, 2);
        _drainSerial();
        return;
      }
      if (!handleCommand(buff[2], buffo - 5, buff + 3)) {
        // Tweak ack + cmd fields to report bad command.
        buff[1] = 0xFF;
        buff[2] = 0xFC;
      } // else success -> just send back the ack + cmd
      Serial.write(buff + 1, 2);
      buffo = 0;
    }
    if (buffo == 2 && buff[0] == buff[1] && buff[1] == 0xF0) {
      // I have no clue why I'm getting F0F0 at the start... but it's not right
      buffo = 0;
    }
  }
}

int last_poll = 0;

// Knob state:
// KnobId: 5 bits = 32 knobs
// State: Rot{left, right} Button{down, up}
// All none = 0 and shouldn't be sent.
//     0: Left
//     1: Right
//     2: Down
//     3: Up
// If two states pop up in the same loop(), its just two 19 / 0x13 commands.
#define BUTTON_STATE_ENC(id, state) ((id << 3) | (state))
#define BUTTON_LEFT  0
#define BUTTON_RIGHT 1
#define BUTTON_DOWN  2
#define BUTTON_UP    3

#define SIGNAL_BUTTON(id, state) \
  _signal_state[index++] = BUTTON_STATE_ENC(id, state); \
  _signal_state[index++] = 0x13;

void loop() {
  // Check the serial buffer as fast as possible...
  readSerial();

  // ... but service the switches at a lower rate.
  int val = millis();
  if (val - last_poll < 5) return;
  last_poll = val;

  byte _signal_state[(encsl + butsl) * 2];
  int index = 0;

  int i;
  for (i = 0; i < encsl; i++) {
    val = encs[i].poll();
    if (val == -1) {
      SIGNAL_BUTTON(i, BUTTON_LEFT);
    } else if (val == 1) {
      SIGNAL_BUTTON(i, BUTTON_RIGHT);
    }
  }

  for (i = 0; i < butsl; i++) {
    val = buts[i].poll();
    if (val == -1) {
      SIGNAL_BUTTON(i, BUTTON_UP);
    } else if (val == 1) {
      SIGNAL_BUTTON(i, BUTTON_DOWN);
    }
  }

  if (index > 0) {
    Serial.write(_signal_state, index);
  }
}

