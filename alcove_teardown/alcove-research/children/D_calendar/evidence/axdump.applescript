on run argv
  set winName to item 1 of argv
  set out to ""
  tell application "System Events" to tell process "Alcove"
    set els to entire contents of (first window whose name is not "")
    repeat with e in els
      try
        set r to role of e
        set t to ""
        try
          set t to title of e
        end try
        set v to ""
        try
          set v to value of e as string
        end try
        set d to ""
        try
          set d to description of e
        end try
        set p to position of e
        set s to size of e
        set out to out & r & " | t=" & t & " | v=" & v & " | d=" & d & " | " & (item 1 of p) & "," & (item 2 of p) & " " & (item 1 of s) & "x" & (item 2 of s) & linefeed
      end try
    end repeat
  end tell
  return out
end run
