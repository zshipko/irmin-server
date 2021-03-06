module type S = sig
  type hash

  type tree

  val tree_t : tree Irmin.Type.t

  val hash_t : hash Irmin.Type.t

  module Info : Irmin.Info.S

  type t = { info : Info.t; parents : hash list; hash : hash; tree : tree }
  [@@deriving irmin]

  val info : t -> Info.t

  val hash : t -> hash

  val parents : t -> hash list

  val tree : t -> tree

  val v : info:Info.t -> parents:hash list -> hash:hash -> tree:tree -> t
end

module type Commit = sig
  module type S = S

  module Make (S : Irmin.S) (T : Tree.S) :
    S with type hash = S.Hash.t and type tree = T.t and module Info = S.Info
end
