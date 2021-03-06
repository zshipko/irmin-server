open Cmdliner
open Lwt.Syntax
open Lwt.Infix
open Import
open Irmin_server_types

let with_timer f =
  let t0 = Sys.time () in
  let+ a = f () in
  let t1 = Sys.time () -. t0 in
  (t1, a)

let init ~uri ~branch ~tls (module Client : Irmin_client.S) : client Lwt.t =
  let* x = Client.connect ~tls ~uri () in
  let+ () =
    match branch with
    | Some b ->
        Client.Branch.set_current x
          (Irmin.Type.of_string Client.Branch.t b |> Result.get_ok)
        >|= Error.unwrap "Branch.set_current"
    | None -> Lwt.return_unit
  in
  S ((module Client : Irmin_client.S with type t = Client.t), x)

let run f time iterations =
  let rec eval iterations =
    if iterations = 0 then Lwt.return_unit
    else
      let* () = f () in
      eval (iterations - 1)
  in
  let x =
    if time then (
      let+ n, x = with_timer (fun () -> eval iterations) in
      Logs.app (fun l -> l "Time: %fs" (n /. float_of_int iterations));
      x)
    else f ()
  in
  Lwt_main.run x

let list_server_commands () =
  let module Store = Irmin_mem.KV.Make (Irmin.Contents.String) in
  let module Cmd = Irmin_server_types.Command.Make (Store) in
  let str t =
    Fmt.to_to_string Irmin.Type.pp_ty t
    |> String.split_on_char '\n' |> String.concat "\n\t\t"
  in
  List.iter
    (fun (name, (module C : Cmd.CMD)) ->
      Printf.printf "%s:\n\tInput: %s\n\tOutput: %s\n" name (str C.Req.t)
        (str C.Res.t))
    Cmd.commands

let ping client =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let+ result = Client.ping client in
      let () = Error.unwrap "ping" result in
      Logs.app (fun l -> l "OK"))

let find client key =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let key = Irmin.Type.of_string Client.Key.t key |> Error.unwrap "key" in
      let* result = Client.Store.find client key >|= Error.unwrap "find" in
      match result with
      | Some data ->
          let* () =
            Lwt_io.printl (Irmin.Type.to_string Client.Contents.t data)
          in
          Lwt_io.flush Lwt_io.stdout
      | None ->
          Logs.err (fun l -> l "Not found: %a" (Irmin.Type.pp Client.Key.t) key);
          Lwt.return_unit)

let mem client key =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let key = Irmin.Type.of_string Client.Key.t key |> Error.unwrap "key" in
      let* result = Client.Store.mem client key >|= Error.unwrap "mem" in
      Lwt_io.printl (if result then "true" else "false"))

let mem_tree client key =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let key = Irmin.Type.of_string Client.Key.t key |> Error.unwrap "key" in
      let* result =
        Client.Store.mem_tree client key >|= Error.unwrap "mem_tree"
      in
      Lwt_io.printl (if result then "true" else "false"))

let set client key author message contents =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let key = Irmin.Type.of_string Client.Key.t key |> Error.unwrap "key" in
      let contents =
        Irmin.Type.of_string Client.Contents.t contents
        |> Error.unwrap "contents"
      in
      let info = Client.Info.v ~author "%s" message in
      let+ () =
        Client.Store.set client key ~info contents >|= Error.unwrap "set"
      in
      Logs.app (fun l -> l "OK"))

let remove client key author message =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let key = Irmin.Type.of_string Client.Key.t key |> Error.unwrap "key" in
      let info = Client.Info.v ~author "%s" message in
      let+ () =
        Client.Store.remove client key ~info >|= Error.unwrap "remove"
      in
      Logs.app (fun l -> l "OK"))

let export client filename =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let* slice = Client.export client >|= Error.unwrap "export" in
      let s = Irmin.Type.(unstage (to_bin_string Client.slice_t) slice) in
      Lwt_io.chars_to_file filename (Lwt_stream.of_string s))

let import client filename =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let* slice = Lwt_io.chars_of_file filename |> Lwt_stream.to_string in
      let slice =
        Irmin.Type.(unstage (of_bin_string Client.slice_t) slice)
        |> Error.unwrap "slice"
      in
      let+ () = Client.import client slice >|= Error.unwrap "import" in
      Logs.app (fun l -> l "OK"))

let stats client =
  run (fun () ->
      client >>= fun (S ((module Client), client)) ->
      let* stats = Client.stats client >|= Error.unwrap "stats" in
      Lwt_io.printl (Irmin.Type.to_json_string Client.stats_t stats))

let watch client =
  Lwt_main.run
    ( client >>= fun (S ((module Client), client)) ->
      let pp = Irmin.Type.pp Client.Commit.t in
      Client.watch
        (fun x ->
          match x with
          | `Updated (a, b) ->
              Logs.app (fun l -> l "Updated (%a, %a)" pp a pp b);
              Lwt.return_ok `Continue
          | `Added a ->
              Logs.app (fun l -> l "Added %a" pp a);
              Lwt.return_ok `Continue
          | `Removed a ->
              Logs.app (fun l -> l "Removed %a" pp a);
              Lwt.return_ok `Continue)
        client
      >|= Error.unwrap "watch" )

let pr_str = Format.pp_print_string

let key index =
  let doc = Arg.info ~docv:"PATH" ~doc:"Key to lookup or modify" [] in
  Arg.(required & pos index (some string) None & doc)

let filename index =
  let doc = Arg.info ~docv:"PATH" ~doc:"Filename" [] in
  Arg.(required & pos index (some string) None & doc)

let author =
  let doc = Arg.info ~docv:"NAME" ~doc:"Commit author name" [ "author" ] in
  Arg.(value & opt string "irmin-client" & doc)

let message =
  let doc = Arg.info ~docv:"MESSAGE" ~doc:"Commit message" [ "message" ] in
  Arg.(value & opt string "" & doc)

let branch =
  let doc = Arg.info ~docv:"BRANCH" ~doc:"Branch name" [ "branch" ] in
  Arg.(value & opt (some string) None & doc)

let value index =
  let doc = Arg.info ~docv:"DATA" ~doc:"Value" [] in
  Arg.(required & pos index (some string) None & doc)

let tls =
  let doc = Arg.info ~doc:"Enable TLS" [ "tls" ] in
  Arg.(value @@ flag doc)

let time =
  let doc = Arg.info ~doc:"Enable timing" [ "time" ] in
  Arg.(value @@ flag doc)

let iterations =
  let doc =
    Arg.info ~doc:"Iterations when timing is enabled" [ "i"; "iterations" ]
  in
  Arg.(value @@ opt int 1 doc)

let freq =
  let doc = Arg.info ~doc:"Update frequency" [ "f"; "freq" ] in
  Arg.(value @@ opt float 5. doc)

let config =
  let create uri (branch : string option) tls (store, hash, contents)
      config_path () =
    let config =
      match uri with
      | Some uri -> Irmin_http.config uri
      | None -> Irmin_mem.config ()
    in
    let store, config =
      Irmin_unix.Resolver.load_config ?config_path ~default:config ~store ~hash
        ~contents ()
    in
    let (module Store : Irmin.S), _ =
      Irmin_unix.Resolver.Store.destruct store
    in
    let module Client = Irmin_client.Make (Store) in
    let uri =
      Irmin.Private.Conf.(get config Irmin_http.uri)
      |> Option.value ~default:Cli.default_uri
    in
    init ~uri ~branch ~tls (module Client)
  in
  Term.(
    const create $ Cli.uri $ branch $ tls $ Cli.store $ Cli.config_path
    $ Cli.setup_log)

let help =
  let help () =
    Printf.printf "See output of `%s --help` for usage\n" Sys.argv.(0)
  in
  (Term.(const help $ Term.pure ()), Term.info "irmin-client")

let () =
  Term.exit
  @@ Term.eval_choice help
       [
         ( Term.(const list_server_commands $ pure ()),
           Term.info ~doc:"List all commands available on server"
             "list-commands" );
         ( Term.(const ping $ config $ time $ iterations),
           Term.info ~doc:"Ping the server" "ping" );
         ( Term.(const find $ config $ key 0 $ time $ iterations),
           Term.info ~doc:"Get the key associated with a value" "get" );
         ( Term.(const find $ config $ key 0 $ time $ iterations),
           Term.info ~doc:"Alias for 'get' command" "find" );
         Term.
           ( const set $ config $ key 0 $ author $ message $ value 1 $ time
             $ iterations,
             Term.info ~doc:"Set key/value" "set" );
         Term.
           ( const remove $ config $ key 0 $ author $ message $ time $ iterations,
             Term.info ~doc:"Remove value associated with the given key"
               "remove" );
         ( Term.(const import $ config $ filename 0 $ time $ iterations),
           Term.info ~doc:"Import from dump file" "import" );
         ( Term.(const export $ config $ filename 0 $ time $ iterations),
           Term.info ~doc:"Export to dump file" "export" );
         ( Term.(const mem $ config $ key 0 $ time $ iterations),
           Term.info ~doc:"Check if key is set" "mem" );
         ( Term.(const mem_tree $ config $ key 0 $ time $ iterations),
           Term.info ~doc:"Check if key is set to a tree value" "mem_tree" );
         ( Term.(const stats $ config $ time $ iterations),
           Term.info ~doc:"Server stats" "stats" );
         ( Term.(const watch $ config),
           Term.info ~doc:"Watch for updates" "watch" );
         ( Term.(const Dashboard.main $ config $ freq),
           Term.info ~doc:"Run dashboard" "dashboard" );
       ]
