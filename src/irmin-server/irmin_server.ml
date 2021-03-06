include Irmin_server_intf
open Irmin_server_types
module Error = Error

module type S = Server.S

module Make (Store : Irmin.S) = struct
  module X = struct
    include Command
    include Command.Make (Store)
  end

  include Server.Make (X)
end
