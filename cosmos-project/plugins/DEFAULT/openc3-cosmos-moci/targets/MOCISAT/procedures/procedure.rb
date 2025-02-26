# Script Runner test script
cmd("MOCISAT EXAMPLE")
wait_check("MOCISAT STATUS BOOL == 'FALSE'", 5)
