include Commit_intf

module Make (St : Irmin.S) (T : Tree.S) = struct
  type tree = T.t

  let tree_t = T.t

  type hash = St.Hash.t

  let hash_t = St.Hash.t

  module Info = St.Info

  type t = { info : Info.t; parents : hash list; hash : hash; tree : T.t }
  [@@deriving irmin]

  let info { info; _ } = info

  let hash { hash; _ } = hash

  let parents { parents; _ } = parents

  let tree { tree; _ } = tree

  let v ~info ~parents ~hash ~tree = { info; parents; hash; tree }
end
