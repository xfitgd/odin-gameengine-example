package main

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:os"
import "core:strings"


main :: proc() {
	f, ok := os.read_entire_file("build.json")
	if(!ok) {
		fmt.eprintln("err: not found build.json!")
		return
	}
	defer delete(f)
	//fmt.println(string(f))

	if(len(os.args) > 0 && os.args[0] == "install") {

	} else {
		json_data, json_err  := json.parse(f)
		if(json_err != .None) {
			fmt.eprintln("err: json ", json_err)
			return
		}
		//fmt.println(json_data)
	
		setting := (json_data.(json.Object)["setting"]).(json.Object)
	
		if(!setting["is-android"].(json.Boolean)) {
			os.execvp("odin", {"build", setting["main-package-path"].(json.String)})
		}
	}
}