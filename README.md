# ArdKnob

A collection of libraries for talking to arduinos and [FlightGear](www.flightgear.org)
to create physical devices that can interface with the simluation.

[![Build Status](https://travis-ci.org/jtmcdole/ardknob.svg?branch=master)](https://travis-ci.org/jtmcdole/ardknob)
[![Coverage Status](https://coveralls.io/repos/github/jtmcdole/ardknob/badge.svg?branch=master)](https://coveralls.io/github/jtmcdole/ardknob?branch=master)

## Motivation

I want to control my Flightgear, an open source flight sim, nav and radio stacks
with my arduino. I wanted to have multiple rotary encoders and an OLED feedback.
With these libraries, I get pretty good flexiblity rendering text, graphics, and
bitmaps - plus simple feedback from the rotary encoders. I'll add more libraries
as I get integrated with Flightgear.

[YouTube video](https://youtu.be/FwqusukU0Ao) showing bin/arddemo.dart in action

## Overview 

The arduino is a simple serial device with a limited hardware buffer of 64
bytes. The objective is to keep it busy without overflowing.

Commands are sent as soon as possible. If a valid command would exceed the
hardware limit + outstanding commands, it will be placed on a work queue to be
sent when the arduino / serial has caught up. Calling write() will return a 
future that completes when the command has been acknowldged. Commands can fail
for a number of reasons:

* Corruption: the fletch16 checksum helps detect corruption.
* Invalid command: check the firmware, it might be old.
* Stray alpha particle from the sun: I have no clue, but if an acknowlgement
for later work is received, older work should be considered busted. *shurg*

## [ArdProto](ardproto/ardproto-library.html) Design

Basic packet layout includes:

* 1-byte `size` field, includes entire packets. Max 64 bytes.
* 1-byte `user ack` field, to be returned with each successful command.
* 1-byte `command` field.
* X-5 bytes of repeated `data`, max 59 bytes
* 2-byte Fletcher-16 checksum fields that should equal to zero on recieving side.

```
 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
┌─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┐
│     size      │    user ack   │
├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
│    command    │    data0      │
├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
│                               │
│       ... data(size - 5)      │
│                               │
├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
│  flch16-sum2  │  flch16-sum1  │
└─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┘
 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7

```

## [Display](display/display-library.html)

Currently this just sends render commands to the arduino to handle natively.
However, there appears to be a 40ms hit to call display() because it is moving
the _entire_ display buffer over. So there are two options: send raw screen
writes directly to the display (currently, it still takes a chunk of time to
send data on windows / arduino uno) or have Display detect the hit box and send
a new command to update just that region of memory.

## [Pages](pages/pages-library.html)

The pages library provides a simple method for defining and sorting pages to be
displayed on an arduino running the ardknob.ino.

## TODO list

* Reserve some early commands for future work.
* Make the ardknob.ino code a library with simple registration / handling - not
just something dedicated to my display needs.
* Make an initialization request that sends back symbols for each command id as
well as some version information. This would be similar to knob action handling
and carry extra data. ArdProto currently doesn't care what you sent over the
wire, just so long as it fits in the framing.
* Decorated book which will render the current page name for ~1.5 seconds, which
would look like:

```
  ┌────────────┐      ┌────────────┐
  │aaaaaabbbbbb│  1sec│aa╓──────╖bb│
  │            │ <--- │══╣page 1╠══│
  │ccccccdddddd│      │cc╙──────╜dd│
  └────────────┘      └────────────┘
        │                   ^
        V                   |
  ┌────────────┐      ┌────────────┐
  │xx╓──────╖yy│1sec  │xxxxxxyyyyyy│
  │══╣page 2╠══│ ---> │wwwwwwuuuuuu│
  │zz╙──────╜00│      │zzzzzz000000│
  └────────────┘      └────────────┘
```

## Work In Progress

Currently experimenting with examples/widgets for my own board that has 3 rotary encoders that also act as push buttons. Mostly working through widgets and the 128x64 oled. When it's done, I'll make a few more libraries...
