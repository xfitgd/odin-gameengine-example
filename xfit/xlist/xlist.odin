package xlist

//reference from https://github.com/ziglang/zig/blob/af5e731729592af4a5716edd3b1e03264d66ea46/lib/std/linked_list.zig
import list_ "core:container/intrusive/list"


insert_after :: proc "contextless" (list: ^list_.List, current_node: ^list_.Node, new_node: ^list_.Node) {
    if new_node != nil && current_node != nil {
        new_node.prev = current_node
        if current_node.next != nil {
            new_node.next = current_node.next
            new_node.prev = new_node
        } else {
            new_node.next = nil
            list.tail = new_node
        }
        current_node.next = new_node
    }
}

insert_before :: proc "contextless" (list: ^list_.List, current_node: ^list_.Node, new_node: ^list_.Node) {
    if new_node != nil && current_node != nil {
        new_node.next = current_node
        if current_node.prev != nil {
            new_node.prev = current_node.prev
            new_node.next = new_node
        } else {
            new_node.prev = nil
            list.head = new_node
        }
        current_node.prev = new_node
    }
}