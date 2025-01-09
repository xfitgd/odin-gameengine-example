#+private
package xfit

import "glfw"


@(private="file") wnd:glfw.WindowHandle

glfwStart :: proc() {
    //Unless you will be using OpenGL or OpenGL ES with the same window as Vulkan, there is no need to create a context. You can disable context creation with the GLFW_CLIENT_API hint.
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

   // wnd = glfw.CreateWindow()
}


glfwSystemStart :: proc() {

}

glfwSystemDestroy :: proc() {}
