#!/bin/bash
# ax_click.sh X Y : AX-click the control whose position is exactly {X,Y} in the frontmost Alcove window
osascript -e "tell application \"System Events\" to tell process \"Alcove\"
set w to (first window whose name is not \"\")
set els to entire contents of w
repeat with e in els
  try
    set p to position of e
    if (item 1 of p is $1) and (item 2 of p is $2) then
      click e
      delay 0.4
      return (class of e as string) & \" clicked, value now \" & ((value of e) as string)
    end if
  end try
end repeat
return \"not found\"
end tell"
