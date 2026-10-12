tell application "Calendar"
  set out to ""
  repeat with c in calendars
    set n to name of c
    set evs to (every event of c whose start date > ((current date) - 1 * days) and start date < ((current date) + 6 * days))
    repeat with e in evs
      set out to out & n & " | " & summary of e & " | " & (start date of e as string) & " | allday=" & (allday event of e) & linefeed
    end repeat
  end repeat
  return out
end tell
