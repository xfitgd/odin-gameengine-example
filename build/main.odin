package main

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:sys/linux"


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
		o:string
		debug:bool = false
		if strings.compare(setting["build-type"].(json.String), "minimal") == 0 {
			o = "-o:minimal"
			debug = true
		} else {
			o = strings.join({"-o:", setting["build-type"].(json.String)}, "", context.temp_allocator)
		}
		//defer free_all(	context.temp_allocator)

		r, w, err := os2.pipe()
		if err != nil do panic("pipe")

		p: os2.Process
		p, err = os2.process_start(os2.Process_Desc{
			command = {"/usr/local/odin/odin", "build", 
			setting["main-package-path"].(json.String), 
			"-no-bounds-check" if !debug else ({}),
			out_path, 
			o, 
			"-debug" if debug else ({}),
			({}) if !is_android else "-define:__ANDROID__=true"},
			stdout  = w,
			stderr  = w,
		})
		os2.close(w)
	
		output, err2 := os2.read_entire_file_from_file(r, context.temp_allocator)
		if err2 != nil do fmt.panicf("read_entire_file_from_file %v", err)

		if err != nil {
			fmt.eprint(string(output))
			fmt.panicf("%v", err)
		} else {
			state:os2.Process_State
			state, err = os2.process_wait(p)

			if state.exit_code != 0 {
				fmt.eprint(string(output))

				os2.close(r)
				_ = os2.process_close(p)
				os.exit(-1)
			}

			fmt.print(string(output))
			if err != nil do panic("process_wait")
		}
		_ = os2.process_close(p)
		os2.close(r)

		if is_android {
		}
	}
}