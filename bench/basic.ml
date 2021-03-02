open Bench_common
open Lwt.Syntax
open Lwt.Infix
module Rpc = Irmin_server.KV (Irmin.Contents.String)
module Client = Rpc.Client

let unwrap = Irmin_server.Error.unwrap

let rec add client tree n =
  if n = 0 then Lwt.return tree
  else
    let s = String.make 1024 'A' in
    let key = [ string_of_int n ] in
    let* tree = Client.Tree.add client tree key s >|= unwrap "add" in
    add client tree (n - 1)

let rpc count =
  let+ n, () =
    let conf = Rpc.Client.conf ~uri:"tcp://127.0.0.1:8888" () in
    let* client = Client.connect conf in
    let* tree = Client.Tree.empty client >|= unwrap "rpc" in

    with_timer (fun () ->
        Logs.app (fun l -> l "Adding items to tree ");
        let* tree = add client tree count in

        Logs.app (fun l -> l "Setting tree");
        let* _ =
          Client.Store.set_tree client ~info:(Irmin_unix.info "test") [ "a" ]
            tree
          >|= unwrap "set_tree"
        in

        Logs.app (fun l -> l "Done setting tree");
        Lwt.return_unit)
  in
  Logs.app (fun l -> l "%f" n)

let () = Lwt_main.run (rpc (try int_of_string Sys.argv.(1) with _ -> 10_000))
