tell application "Calendar"
  if not (exists calendar "Work") then make new calendar with properties {name:"Work", color:{10000, 30000, 65535}}
  if not (exists calendar "Personal") then make new calendar with properties {name:"Personal", color:{20000, 55000, 20000}}
  set now to current date
  set t0 to now - (seconds of now) -- whole minute
  tell calendar "Work"
    make new event with properties {summary:"Design sync", start date:(t0 + 6 * minutes), end date:(t0 + 36 * minutes), location:"Room 4"}
    make new event with properties {summary:"Budget review", start date:(t0 + 10 * minutes), end date:(t0 + 40 * minutes)}
    make new event with properties {summary:"1:1 with Sam", start date:(t0 + 21 * minutes), end date:(t0 + 51 * minutes)}
  end tell
  tell calendar "Personal"
    make new event with properties {summary:"Dentist", start date:(t0 + 85 * minutes), end date:(t0 + 145 * minutes)}
    set d to current date
    set time of d to 0
    make new event with properties {summary:"Launch day", start date:d, end date:(d + 1 * days), allday event:true}
    make new event with properties {summary:"Trip to Tahoe", start date:(d + 3 * days), end date:(d + 5 * days), allday event:true}
    make new event with properties {summary:"Team dinner", start date:(d + 1 * days + 18 * hours), end date:(d + 1 * days + 20 * hours)}
  end tell
  tell calendar "Calendar"
    make new event with properties {summary:"Gym", start date:(d + 2 * days + 7 * hours), end date:(d + 2 * days + 8 * hours)}
  end tell
end tell
tell application "Contacts"
  set bd to current date
  set year of bd to 1990
  set p to make new person with properties {first name:"Alex", last name:"Birthday", birth date:bd}
  save
end tell
