open Lwt.Syntax

module Make (Store : Command_intf.STORE) = struct
  include Context.Make (Store)

  module Empty = struct
    module Req = struct
      type t = unit [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.empty"

    let run conn ctx () =
      let empty = Store.Tree.empty in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id empty;
      Return.v conn Res.t (ID id)
  end

  module Add = struct
    module Req = struct
      type t = Tree.t * Store.key * Store.contents [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.add"

    let run conn ctx (tree, key, value) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.add tree key value in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn Res.t (ID id)
  end

  module Add_hash = struct
    module Req = struct
      type t = Tree.t * Store.key * Store.Hash.t [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.add_hash"

    let run conn ctx (tree, key, value) =
      let* _, tree = resolve_tree ctx tree in
      let* value = Store.Contents.of_hash ctx.repo value in
      let* tree = Store.Tree.add tree key (Option.get value) in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn Res.t (ID id)
  end

  module Add_multiple_hash = struct
    module Req = struct
      type t = Tree.t * (Store.key * Store.Hash.t) list [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.add_multiple_hash"

    let run conn ctx (tree, l) =
      let* _, tree = resolve_tree ctx tree in
      let* tree =
        Lwt_list.fold_left_s
          (fun tree (key, value) ->
            let* value = Store.Contents.of_hash ctx.repo value in
            Store.Tree.add tree key (Option.get value))
          tree l
      in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn Res.t (ID id)
  end

  module Add_tree = struct
    module Req = struct
      type t = Tree.t * Store.key * Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.add_tree"

    let run conn ctx (tree, key, tr) =
      let* _, tree = resolve_tree ctx tree in
      let* _, tree' = resolve_tree ctx tr in
      let* tree = Store.Tree.add_tree tree key tree' in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn Res.t (ID id)
  end

  module Find = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    module Res = struct
      type t = Store.contents option [@@deriving irmin]
    end

    let name = "tree.find"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* contents = Store.Tree.find tree key in
      Return.v conn Res.t contents
  end

  module Find_tree = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t option [@@deriving irmin]
    end

    let name = "tree.find_tree"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.find_tree tree key in
      let tree =
        Option.map
          (fun tree ->
            let id = incr_id () in
            Hashtbl.replace ctx.trees id tree;
            Tree.ID id)
          tree
      in
      Return.v conn Res.t tree
  end

  module Remove = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.t [@@deriving irmin]
    end

    let name = "tree.remove"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Store.Tree.remove tree key in
      let id = incr_id () in
      Hashtbl.replace ctx.trees id tree;
      Return.v conn Res.t (ID id)
  end

  module Cleanup = struct
    module Req = struct
      type t = Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = unit [@@deriving irmin]
    end

    let name = "tree.cleanup"

    let run conn ctx tree =
      let () =
        match tree with Tree.ID id -> Hashtbl.remove ctx.trees id | _ -> ()
      in
      Return.ok conn
  end

  module To_local = struct
    module Req = struct
      type t = Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = Tree.Local.concrete [@@deriving irmin]
    end

    let name = "tree.to_local"

    let run conn ctx tree =
      let* _, tree = resolve_tree ctx tree in
      let* tree = Tree.Local.to_concrete tree in
      Return.v conn Res.t tree
  end

  module Mem = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    module Res = struct
      type t = bool [@@deriving irmin]
    end

    let name = "tree.mem"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* res = Store.Tree.mem tree key in
      Return.v conn Res.t res
  end

  module Mem_tree = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    module Res = struct
      type t = bool [@@deriving irmin]
    end

    let name = "tree.mem_tree"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* res = Store.Tree.mem_tree tree key in
      Return.v conn Res.t res
  end

  module List = struct
    module Req = struct
      type t = Tree.t * Store.key [@@deriving irmin]
    end

    type tree = [ `Contents | `Tree ] [@@deriving irmin]

    module Res = struct
      type t = (Store.Key.step * [ `Contents | `Tree ]) list [@@deriving irmin]
    end

    let name = "tree.list"

    let run conn ctx (tree, key) =
      let* _, tree = resolve_tree ctx tree in
      let* l = Store.Tree.list tree key in
      let* x =
        Lwt_list.map_s
          (fun (k, _) ->
            let+ exists = Store.Tree.mem_tree tree (Store.Key.rcons key k) in
            if exists then (k, `Tree) else (k, `Contents))
          l
      in
      Return.v conn Res.t x
  end

  module Clear = struct
    module Req = struct
      type t = Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = unit [@@deriving irmin]
    end

    let name = "tree.clear"

    let run conn ctx tree =
      let* _, tree = resolve_tree ctx tree in
      Store.Tree.clear tree;
      Return.v conn Res.t ()
  end

  module List_ignore = struct
    module Req = struct
      type t = Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = unit [@@deriving irmin]
    end

    let name = "tree.list_ignore"

    let run conn ctx tree =
      let* _, tree = resolve_tree ctx tree in
      let* _ = Store.Tree.list tree [] in
      Return.v conn Res.t ()
  end

  module Hash = struct
    module Req = struct
      type t = Tree.t [@@deriving irmin]
    end

    module Res = struct
      type t = Store.Hash.t [@@deriving irmin]
    end

    let name = "tree.hash"

    let run conn ctx tree =
      let* _, tree = resolve_tree ctx tree in
      let hash = Store.Tree.hash tree in
      Return.v conn Res.t hash
  end

  module Reset_all = struct
    module Req = struct
      type t = unit [@@deriving irmin]
    end

    module Res = struct
      type t = unit [@@deriving irmin]
    end

    let name = "tree.reset_all"

    let run conn ctx () =
      reset_trees ctx;
      Return.v conn Res.t ()
  end

  let commands =
    [
      cmd (module Empty);
      cmd (module Add);
      cmd (module Add_hash);
      cmd (module Add_multiple_hash);
      cmd (module Remove);
      cmd (module Cleanup);
      cmd (module Mem);
      cmd (module Mem_tree);
      cmd (module List);
      cmd (module To_local);
      cmd (module Find);
      cmd (module Find_tree);
      cmd (module Add_tree);
      cmd (module Clear);
      cmd (module List_ignore);
      cmd (module Hash);
    ]
end
