#!/bin/bash
# list controls (class, value, description, position) of the frontmost Alcove settings window
osascript -e 'tell application "System Events" to tell process "Alcove"
set w to (first window whose name is not "")
set out to (name of w) & linefeed
set els to entire contents of w
repeat with e in els
  try
    set c to class of e
    if c is checkbox or c is pop up button or c is slider or c is radio button or c is button or c is static text then
      set d to ""
      try
        set d to description of e
      end try
      set v to ""
      try
        set v to (value of e) as string
      end try
      if c is not static text or (length of v) < 40 then
        set out to out & (c as string) & " | v=" & v & " | d=" & d & " | " & (position of e as string) & " | " & (size of e as string) & linefeed
      end if
    end if
  end try
end repeat
return out
end tell'
