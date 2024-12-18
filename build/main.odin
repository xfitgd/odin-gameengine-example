package main

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:os"
import "core:strings"


read_build_json :: proc() -> (json.Value, bool) {
	f, ok := os.read_entire_file("build.json")
	if(!ok) {
		fmt.eprintln("err: not found build.json!")
		return nil, false
	}
	//fmt.println(string(f))
	defer delete(f)

	json_data, json_err  := json.parse(f)
	if(json_err != .None) {
		fmt.eprintln("err: json ", json_err)
		return nil, false
	}
	return json_data, true
}

/*
arm-linux-gnueabi
aarch64-linux-gnu
i686-linux-gnu
x86_64-linux-gnu
riscv64-linux-gnu
*/

main :: proc() {
	//fmt.println(os.args)
	json_data:json.Value
	ok :bool

	if len(os.args) > 1 && os.args[1] == "install" {
	} else if len(os.args) > 1 && os.args[1] == "clean" {
		if json_data, ok = read_build_json() ; !ok {return}
		defer json.destroy_value(json_data)
		setting := (json_data.(json.Object)["setting"]).(json.Object)

		os.remove(setting["out-path"].(json.String))
	} else {
		if json_data, ok = read_build_json() ; !ok {return}
		defer json.destroy_value(json_data)
		//fmt.println(json_data)
	
		setting := (json_data.(json.Object)["setting"]).(json.Object)
	
		is_android := setting["is-android"].(json.Boolean);
		out_path := strings.join({"-out:", setting["out-path"].(json.String)}, "")
		defer delete(out_path)

		// Sets the optimization mode for compilation.
		// Available options:
		// 		-o:none
		// 		-o:minimal
		// 		-o:size
		// 		-o:speed
		// 		-o:aggressive (use this with caution)
		// The default is -o:minimal.
		

		os.make_directory("bin")
		if strings.compare(setting["build-type"].(json.String), "minimal") == 0 {
			os.execvp("odin", {"build", setting["main-package-path"].(json.String), "-debug",  out_path, ({}) if !is_android else "-define:__ANDROID__=true"})
		} else {
			o := strings.join({"-o:", setting["build-type"].(json.String)}, "")
			defer delete(o)
			os.execvp("odin", {"build", setting["main-package-path"].(json.String), "-no-bounds-check",  out_path, o, ({}) if !is_android else "-define:__ANDROID__=true"})
		}

		if is_android {
		}
	}
}