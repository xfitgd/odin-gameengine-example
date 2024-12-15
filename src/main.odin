package main

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"

wf::union {
	bool,
	i32,
	string,
}

main :: proc() {
	a := matrix[2, 3]f32{
		2, 3, 1,
		4, 5, 0,
	}
	
	b := matrix[3, 2]f32{
		1, 2,
		3, 4,
		5, 6,
	}
	
	fmt.println("a", a)
	fmt.println("b", b)
	
	c := a * b
	#assert(type_of(c) == matrix[2, 2]f32)
	fmt.println(c)			
}