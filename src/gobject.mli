(* $Id$ *)

type -'a obj
type g_type
type g_class
type g_value
type g_closure
type basic =
  [ `BOOL of bool
  | `CHAR of char
  | `FLOAT of float
  | `INT of int
  | `INT64 of int64
  | `POINTER of Gpointer.boxed option
  | `STRING of string option ]

type data_get = [ basic | `NONE | `OBJECT of unit obj option ]
type 'a data_set =
  [ basic | `OBJECT of 'a obj option | `INT32 of int32 | `LONG of nativeint ]

type data_kind =
  [ `BOOLEAN
  | `BOXED
  | `CHAR
  | `DOUBLE
  | `ENUM
  | `FLAGS
  | `FLOAT
  | `INT
  | `INT64
  | `LONG
  | `OBJECT
  | `POINTER
  | `STRING
  | `UCHAR
  | `UINT
  | `UINT64
  | `ULONG ]

type fundamental_type =
  [ `BOOLEAN
  | `BOXED
  | `CHAR
  | `DOUBLE
  | `ENUM
  | `FLAGS
  | `FLOAT
  | `INT
  | `INT64
  | `INTERFACE
  | `INVALID
  | `LONG
  | `NONE
  | `OBJECT
  | `PARAM
  | `POINTER
  | `STRING
  | `UCHAR
  | `UINT
  | `UINT64
  | `ULONG ]

type 'a data_conv =
    { kind : data_kind; proj : data_get -> 'a; inj : 'a -> unit data_set }

type ('a, 'b) property = { name : string; classe : 'a; conv : 'b data_conv }

exception Cannot_cast of string * string

val get_type : 'a obj -> g_type
val is_a : 'a obj -> string -> bool
val unsafe_cast : 'a obj -> 'b obj
val try_cast : 'a obj -> string -> 'b obj
val coerce : 'a -> [ `base ] obj
val get_oid : 'a obj -> int

type +'a param
val dyn_param : string -> 'a data_set -> 'b param
val param : ('a,'b) property -> 'b -> 'a param

val make : classe:string -> 'a param list -> 'a obj
    (* This type is NOT safe *)

val set : ('a, 'b) property -> 'a obj -> 'b -> unit
val get : ('a, 'b) property -> 'a obj -> 'b
val set_params : 'a obj -> 'a param list -> unit

module Type :
  sig
    val init : unit -> unit
    val name : g_type -> string
    val from_name : string -> g_type
    val parent : g_type -> g_type
    val depth : g_type -> int
    val is_a : g_type -> g_type -> bool
    val fundamental : g_type -> fundamental_type
    val of_fundamental : fundamental_type -> g_type
    val interface_prerequisites : g_type -> g_type list
      
      (* [Benjamin] Experimental stub: the new class has the same size as 
      its parent. No init functions right now. *)
    val register_static : parent:g_type -> name:string -> g_type
  end

module Value :
  sig
    val create_empty : unit -> g_value
    val init : g_value -> g_type -> unit
    val create : g_type -> g_value
    val release : g_value -> unit
    val get_type : g_value -> g_type
    val copy : g_value -> g_value -> unit
    val reset : g_value -> unit
    val type_compatible : g_type -> g_type -> bool
    val type_transformable : g_type -> g_type -> bool
    val transform : g_value -> g_value -> bool
    val get : g_value -> data_get
    val set : g_value -> 'a data_set -> unit
    val get_pointer : g_value -> Gpointer.boxed
    val get_nativeint : g_value -> nativeint
  end

module Closure :
  sig
    type args
    type argv = { result : g_value; nargs : int; args : args; }
    val create : (argv -> unit) -> g_closure
    val nth : argv -> pos:int -> g_value
    val result : argv -> g_value
    val get_result_type : argv -> g_type
    val get_type : argv -> pos:int -> g_type
    val get : argv -> pos:int -> data_get
    val set_result : argv -> 'a data_set -> unit
    val get_args : argv -> data_get list
    val get_pointer : argv -> pos:int -> Gpointer.boxed
    val get_nativeint : argv -> pos:int -> nativeint
    val get_int32 : argv -> pos:int -> int32
  end

module Data :
  sig
    val boolean : bool data_conv
    val char : char data_conv
    val uchar : char data_conv
    val int : int data_conv
    val uint : int data_conv
    val long : int data_conv
    val ulong : int data_conv
    val flags : ([>  ] as 'a) Gpointer.variant_table -> 'a list data_conv
    val enum : ([>  ] as 'a) Gpointer.variant_table -> 'a data_conv
    val int64 : int64 data_conv
    val uint64 : int64 data_conv
    val float : float data_conv
    val double : float data_conv
    val string : string data_conv
    val string_option : string option data_conv
    val pointer : Gpointer.boxed option data_conv
    val unsafe_pointer : 'a data_conv
    val unsafe_pointer_option : 'a option data_conv
    val boxed : Gpointer.boxed option data_conv
    val gobject : 'a obj data_conv
    val gobject_option : 'a obj option data_conv
    val of_value : 'a data_conv -> g_value -> 'a
    val to_value : 'a data_conv -> 'a -> g_value
  end

module Property :
  sig
    val freeze_notify : 'a obj -> unit
    val thaw_notify : 'a obj -> unit
    val notify : 'a obj -> string -> unit
    val set_property : 'a obj -> string -> g_value -> unit
    val get_property : 'a obj -> string -> g_value -> unit
    val get_property_type : 'a obj -> string -> g_type
    val set_dyn : 'a obj -> string -> 'b data_set -> unit
    val get_dyn : 'a obj -> string -> data_get
    val set : 'a obj -> ('a, 'b) property -> 'b -> unit
    val get : 'a obj -> ('a, 'b) property -> 'b
    val get_some : 'a obj -> ('a, 'b option) property -> 'b
    val check : 'a obj -> ('a, 'b) property -> unit
    val may_cons :
      ('a,'b) property -> 'b option -> 'a param list -> 'a param list
    val may_cons_opt :
      ('a,'b option) property -> 'b option -> 'a param list -> 'a param list
  end

