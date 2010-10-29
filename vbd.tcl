# vbd.tcl
#
# Generates ASCII block diagrams from vhdl code.  
#
# USAGE 
#
# tclsh vbd.tcl FILE...
#
# Ports in the vhdl code must be std_logic or std_logic_vector, and declared 
# on seperate lines. 
#
# Generated block diagrams show inputs on the left, outputs and bidirectional 
# signals on the right. Vector signals are marked with square brackets. 
# Ports are grouped according to port declaration groups in the vhdl code.

# Opens a file, reads in its entity port construct, and populates an inputs and 
# outputs list. Returns the two lists as a single two dimensional list if the
# parse is successful. Each list is a set of strings with the format 
# "port group number~port name", e.g. "0~clk".
proc parsePorts {filename} {
    
    set context SEARCHING_FOR_ENTITY
    set portGroup 0
    set portGroupEmpty 1
    set inputs [list]
    set outputs [list]
    
    set infile [open "$filename" r]
    while {[gets $infile aLine] >= 0} {
        
        # if aLine is a just a comment line then skip it
        if {[regexp {^\s*--} $aLine]} {
            continue
        }       
        
        # if we haven't got to a entity construct yet
        if {[string equal $context SEARCHING_FOR_ENTITY]} {
            if {[regexp -nocase {\mentity\M} $aLine]} {
                set context IN_ENTITY
            }
        }
        
        # if we are in an entity but not in port construct 
        if {[string equal $context IN_ENTITY]} {
            if {[regexp -nocase {\mport\M} $aLine]} {
                set context IN_ENTITY_PORT
            }
        }
        
        # if we are inside an entity port construct 
        if {[string equal $context IN_ENTITY_PORT]} {
            
            # if we have got to the end of port construct
            if {[regexp -nocase {\mend\M} $aLine]} {
                set context COMPLETE
                break
            }
            
            # if we have an empty line
            if {[regexp {^\s*$} $aLine]} {
                if {$portGroupEmpty} {
                    continue    
                }
                set portGroupEmpty 1
                incr portGroup
                continue 
            }
            
            # if we have a port declaration
            if {[regexp -nocase \
                    {^\s*(\w+)\s*:\s*(in|out|inout|buffer)\s*std_logic(_vector)?} \
                    $aLine match portName direction vector]} {
                set portGroupEmpty 0
                if {[string equal $vector "_vector"]} {
                    set vector "\[\]"   
                }
                if {[string equal -nocase $direction "in"]} {
                    lappend inputs "$portGroup~$portName$vector"
                } else {
                    lappend outputs "$portGroup~$portName$vector"   
                }
            }
            
        }
    }
    close $infile
    
    # return input output lists only if completed successfully
    if {[string equal $context COMPLETE]} {
        return [list $inputs $outputs]  
    }
    return [list]
}

# converts two lists, inputs and outputs, and returns a list containing the
# block diagram
proc getBlockDiagram {inputs outputs} {
    
    set combined [list]
    set inputsIndex 0
    set outputsIndex 0
    set lastGroup 0

    while {1} {

        # if both input and output lists are exhausted we're done
        if {$inputsIndex >= [llength $inputs] && \
                $outputsIndex >= [llength $outputs]} {
            break   
        }
        
        # get next input and output line, or "" if exhausted
        set input ""
        set output ""
        if {$inputsIndex != [llength $inputs]} {
            set input [lindex $inputs $inputsIndex]     
        }
        if {$outputsIndex != [llength $outputs]} {
            set output [lindex $outputs $outputsIndex]  
        }
        
        # get groups and names from input and output
        set inputGroup [lindex [split $input ~] 0]
        set outputGroup [lindex [split $output ~] 0]
        set inputName [lindex [split $input ~] 1]
        set outputName [lindex [split $output ~] 1]
        
        # get group number we are going to do
        if {[string length $output] == 0} {
            set currentGroup $inputGroup
        } elseif {[string length $input] == 0} { 
            set currentGroup $outputGroup
        } elseif {$inputGroup < $outputGroup} {
            set currentGroup $inputGroup
        } else {
            set currentGroup $outputGroup
        }

        # if we have changed to a new group then append a line with no ports
        if {$lastGroup != $currentGroup} {
            lappend combined "~"
            set lastGroup $currentGroup
        }
        
        # if all the outputs are done 
        if {$outputsIndex == [llength $outputs]} {
            lappend combined "$inputName~"
            incr inputsIndex
            continue
        } 
        
        # if all the inputs are done 
        if {$inputsIndex == [llength $inputs]} {
            lappend combined "~$outputName"
            incr outputsIndex
            continue
        }
        
        # if both inputGroup and outputGroup are the same
        if {$inputGroup == $outputGroup} {
            lappend combined "$inputName~$outputName"  
            incr inputsIndex
            incr outputsIndex
            continue
        }

        # if inputGroup equals current group
        if {$inputGroup == $currentGroup} {
            lappend combined "$inputName~"
            incr inputsIndex
            continue
        }

        # if we get to here then outputGroup equals current group
        lappend combined "~$outputName"
        incr outputsIndex
    }
    
    # get the longest combined line
    set longestLength 0
    foreach i $combined {
        if {[string length $i] > $longestLength} {
            set longestLength [string length $i]
        }
    }
    
    # top and bottom horizontal lines
    set horiz [string repeat "-" [expr {$longestLength + 5}]]
    
    # generate all lines for output in a list
    set blockDiagram [list]
    lappend blockDiagram "--"
    lappend blockDiagram "--   $horiz"
    foreach i $combined {
        set numberSpaces [expr {$longestLength - [string length $i] + 4 }]
        regsub {~} $i [string repeat " " $numberSpaces] sized
        lappend blockDiagram "-- --|$sized|--" 
    }
    lappend blockDiagram "--   $horiz"
    lappend blockDiagram "--"
    
    return $blockDiagram;
}

# check we have been supplied with at least one filename
if {$argc < 1} {
    puts "Error, no files supplied"
    return 1
}

# supply block diagram for each filename supplied
set fileIndex 0
while {1} {
    
    set filename [lindex $argv $fileIndex] 
    
    # if more than one file is supplied then print out filename
    if {[llength $argv] > 1} {
        puts $filename  
    }
    
    # check we can read filename
    if {[file readable $filename] == 0} {
        puts "Error reading $filename"
        return 1
    }
    
    set inout [parsePorts $filename];
    
    # if parse ports failed
    if {[llength $inout] == 0} {
        puts "Error parsing $filename"
        return 1;       
    }
    
    set inputs [lindex $inout 0]  
    set outputs [lindex $inout 1]
    
    set blockDiagram [getBlockDiagram $inputs $outputs]
    foreach i $blockDiagram {
        puts $i
    }
    
    # check to see if we have done all the files
    incr fileIndex
    if {$fileIndex == [llength $argv]} {
        return 0;
    }
    puts ""
}


