open Printf

(* Xa file system *)

exception Found_int of int

external read_raw_frame : Unix.file_descr -> int -> string 
    = "read_raw_frame"

exception Error of string

external init : unit -> unit
    = "cd_init"

let _ =
  Callback.register_exception "cd_error" (Error "");
  init ()

(*
let read_raw_frame fd x =
  try
    read_raw_frame fd x
  with
*)

type primary_volume_descriptor = {
    system_id : string;
    volume_id : string;
    application_id : string;
    root_directory_record : string
  } 

type directory_record = {
    extent : int;
    size : int;
    directory : bool;
    name : string
  } 

let read_iso9660_sector fd l =
  let s = read_raw_frame fd l in
  String.sub s 24 2048

let get_num s start last =
  let sum = ref 0 in
  let mul = ref 1 in
  for i = start to last do
    sum := !sum + ((Char.code s.[i]) * !mul);
    mul := !mul * 256
  done;
  !sum
  
let get_float s start last =
  let sum = ref 0.0 in
  let mul = ref 1.0 in
  for i = start to last do
    sum := !sum +. ((float (Char.code s.[i])) *. !mul);
    mul := !mul *. 256.0
  done;
  !sum
  
let get_byte_four s offset = get_num s offset (offset + 4)

let get_string s start last =
  if last - start + 1 <= 0 then "" else
    String.sub s start (last - start + 1)

let parse_directory_record s = (* badly coded *) 
  let s = "#" ^ s in
  let len_dr = get_num s 1 1 in
  if len_dr = 0 then raise Exit;
  let extent = get_num s 3 6 in
  let size = get_num s 11 14 in
  let flags = get_num s 26 26 in
  let len_fi = get_num s 33 33 in
  let name = get_string s 34 (33 + len_fi) in
  { extent= extent;
    size= size;
    directory= flags land 2 <> 0;
    name= name },
  String.sub s (len_dr + 1 (* for "#" *)) (String.length s - (len_dr + 1))
;;

let parse_directory_record_list s =
  let s = ref s in
  let records = ref [] in
  try while true do
    let record, remain = parse_directory_record !s in
    s := remain;
    records := record :: !records
  done; raise Exit with _ -> List.rev !records
;;

let read_primary_volume_descriptor fd =
  let s = read_iso9660_sector fd 16 in
  let s = "#"^s in
  let d =
    { system_id= get_string s 9 40;
      volume_id= get_string s 41 72;
      application_id= get_string s 575 702;
      root_directory_record= get_string s 157 190 } 
  in
  prerr_endline ("system id: " ^ d.system_id);
  prerr_endline ("volume id: " ^ d.volume_id);
  prerr_endline ("application id: " ^ d.application_id);
  d
;;

let locate_file fd name =
  (* split a string according to char_sep predicate *)
  let split_str char_sep str =
    let len = String.length str in
    if len = 0 then [] else
    let rec skip_sep cur =
      if cur >= len then cur
      else if char_sep str.[cur] then skip_sep (succ cur)
      else cur  in
    let rec split beg cur =
      if cur >= len then 
	if beg = cur then []
	else [String.sub str beg (len - beg)]
      else if char_sep str.[cur] 
	   then 
	     let nextw = skip_sep cur in
	      (String.sub str beg (cur - beg))
		::(split nextw nextw)
	   else split beg (succ cur) in
    let wstart = skip_sep 0 in
    split wstart wstart
  in
  let namelist = " " :: (split_str (function '/' -> true | _ -> false) name) in
  let p_v_d = read_primary_volume_descriptor fd in
  let rec search_file record_str = 
    let rec find x = function
	[] -> raise Not_found
      |	y :: ys -> 
	  if x = String.lowercase y.name then y else find x ys
    in
    let records = parse_directory_record_list record_str in
    function 
	[] -> raise Not_found
      |	[x] ->
(*	  prerr_endline ("Searching file " ^x); *)
	  begin
	    try
	      find (x^";1") records (* normal file *)
	    with
	      Not_found -> find x records (* directory *)
	  end
      |	x :: xs ->
(*	  prerr_endline ("Searching dir " ^x); *)
	  let record = find x records in
	  if not record.directory then 
	    raise (Failure (x ^ " is non directory"));
	  search_file (read_iso9660_sector fd record.extent) xs (* I hope <= 2048 *)
  in
  search_file p_v_d.root_directory_record namelist  

let dir fd record =
  parse_directory_record_list (read_iso9660_sector fd record.extent)

type info = {
    tracks : (int * int) list;
    interleave : int
  } 

let track_info s =
  if Char.code s.[18] = 0x64 &&
     Char.code s.[19] = 1 &&
     Char.code s.[20] = 1 &&
     Char.code s.[17] = Char.code s.[21] &&
     Char.code s.[22] = 0x64 then (* alive *)
      Char.code s.[21]
  else 
    -1

let info_file fd record =
  let tracks = ref []
  and first = ref (-1)
  and first_sector = ref (-1)
  and interleave = ref (-1)
  in

  begin try
    for i = 0 to 32 (* 31 + 1 *) do
      let s = read_raw_frame fd (record.extent + i) in
      let track = track_info s in
      if track >= 0 then begin
  	if !first = -1 then begin
	  first := track;
	  first_sector := i
	end else if !first = track then begin (* looped *)
  	  interleave := i - !first_sector;
  	  raise Exit
  	end;
	tracks := (Char.code s.[21],i) :: !tracks
      end
    done
  with Exit -> () end;

  let tracks = List.rev !tracks 
  and interleave = !interleave
  in
  
  prerr_endline (sprintf "Start @ %d" record.extent);
  prerr_endline (sprintf "Interleave %d" interleave);
  prerr_string "Tracks: ";
  List.iter (fun (id,sect) -> prerr_string (sprintf "(#%d= sec%d) " id sect))
    tracks;
  prerr_endline "";
  { tracks= tracks;
    interleave= interleave }
;;

let guess_interleave fd sect = (* this sect must be valid Xa sector *)
  let track = track_info (read_raw_frame fd sect) in
  if track = -1 then raise (Failure "this is not Xa sector");
  try
    for i = 1 to 32 (* 31 + 1 *) do
      let track' = track_info (read_raw_frame fd (sect + i)) in
      if track = track' then raise (Found_int i)
    done; raise (Failure "could not find next sector")
  with
    Found_int i -> i

(* quick checker for xa files. sometimes incorrect *)
let is_xa_file fd sect =
  try guess_interleave fd sect; true with _ -> false 

let diskid fd =
  let files = ref [] in
  let pvd = read_primary_volume_descriptor fd in
  let done_dir = ref [] in
  let rec searcher current s =
    let records = parse_directory_record_list s in
    List.iter (fun record -> 
      if List.mem record.extent !done_dir then ()
      else if record.directory then begin
	prerr_endline  ("DIR: " ^ record.name);
	done_dir := record.extent :: !done_dir;
	searcher (current ^ "/" ^ record.name) 
	  (read_iso9660_sector fd record.extent)
      end else begin 
	prerr_endline  ("FIL: " ^ record.name);
	files := (current ^ "/" ^ record.name) :: !files 
      end) records
  in
  searcher "" pvd.root_directory_record;
  let encoder s = 
    let id = ref "" in
    for i = 0 to String.length s - 1 do
      let code = Char.code s.[i] in
      if code <= Char.code ' ' || code > Char.code '~'  ||
         code = Char.code '/' then
	id := !id ^ (sprintf "%%%02X" code)
      else
	id := !id ^ (String.make 1 s.[i])
    done;
    !id
  in
  encoder (Digest.string (List.fold_right (fun x st ->
    x ^ "::" ^ st) (List.rev !files) ""))

let read_cdrom_info fd =
  let get_string s =
    let s =
      try
	let x = String.index s char: '\000' in
	String.sub s pos:0 len:x
      with
	Not_found -> s
    in
    (* remove spaces at the end *)
    if s = "" then s else begin
      let last = ref (String.length s - 1) in
      try
	while !last >= 0 do
	  match s.[!last] with
	    ' ' -> decr last 
	  | _ -> raise Exit
	done; ""
      with
	Exit -> String.sub s pos:0 len:(!last + 1)
    end
  in
  let pvd = read_primary_volume_descriptor fd in
  let a = get_string pvd.application_id
  and v = get_string pvd.volume_id in
  if a <> "" && v <> "" then a, v
  else
    "PLAYSTATION", diskid fd

let list_xa_files_of_disk fd =
  let xas = ref [] in
  let pvd = read_primary_volume_descriptor fd in
  let done_dir = ref [] in
  let rec searcher s =
    let records = parse_directory_record_list s in
    List.iter (fun record -> 
      if List.mem record.extent !done_dir then ()
      else if record.directory then begin
	prerr_endline  ("DIR: " ^ record.name);
	done_dir := record.extent :: !done_dir;
	searcher (read_iso9660_sector fd record.extent)
      end else begin 
	prerr_endline  ("FIL: " ^ record.name);
	if is_xa_file fd record.extent then
	  xas := record :: !xas
      end) records
  in
  searcher pvd.root_directory_record;
  List.rev !xas

type track = {
    tstart : int;
    mutable tinterleave : int;
    mutable tlength : int;
  } 

exception Found_before of int

let get_tracks fd reporter record =
  let tracks = ref [] in
  let table = Array.create 32 (-1) in
  let start = Array.create 32 (-1) in
  (* this does not work for files with more than one interleave mode *)
  let xa_info = info_file fd record in
  let interleave = xa_info.interleave in

  (* report *)
  let sectors = record.size / 2048 in
  let report_sector = 
    let rs = sectors / 100 in
    if rs = 0 then 1 else rs
  in
  reporter sectors 0;

  for i = record.extent to record.extent + record.size / 2048 - 1 do
    let prevtrack =
      try 
	for j = 0 to 31 do
	  if table.(j) = i - interleave then raise (Found_before j)
	done; 
	-1
      with Found_before j -> j
    in
    let track = track_info (read_raw_frame fd i) in
    if track <> -1 then begin
      if prevtrack = -1 then begin
	prerr_endline (sprintf "found at %d (track %d)" i track);
	start.(track) <- i
      end;
      table.(track) <- i;
    end else begin
      if prevtrack <> -1 then begin
	prerr_endline (sprintf "track %d is end at %d" prevtrack table.(prevtrack));
	table.(prevtrack) <- -1;
	tracks := { tstart= start.(prevtrack); 
		    tinterleave= interleave;
		    tlength= (i - start.(prevtrack)) / interleave} :: !tracks
      end
    end;
    if (i - record.extent) mod report_sector = 0 then 
      reporter sectors (i - record.extent)
  done;
  reporter sectors sectors;
  List.rev !tracks
;;  

(*
let gap_min_length = 24 (* per track *)
let track_min_length = 24 * 8 (* physical *)

let fix_tracks_start fd at =
  let at = ref at in
  let tracks_start = 
    try
      while true do
	if track_info (read_raw_frame fd !at) <> -1 then 
	  raise (Found_int !at);
	incr at
      done; -1
    with
      Found_int x -> x
  in
  prerr_endline ("Found the first track starts @ " ^ string_of_int tracks_start);
  let first = ref (-1) in
  let first_sector = ref (-1) in
  let tracks = ref [] in
  try
    for i = 0 to 32 (* 31 + 1 *) do
      let id = track_info (read_raw_frame fd (tracks_start + i)) in
      if id <> -1 then begin
	if !first = (-1) then begin
	  first := id;
	  first_sector := tracks_start + i
	end else begin
	  if !first = id then raise (Found_int (tracks_start + i - !first_sector))
	end;
	prerr_endline (sprintf "Track #%d starts @ %d" id (tracks_start + i));
	tracks := (id, { tstart= tracks_start + i;
			 tlength= -1;
			 tinterleave= -1 }) :: !tracks
      end
    done; raise (Failure "could not find interleave length") 
  with
    Found_int inter ->
      List.iter (fun (_,x) -> x.tinterleave <- inter) !tracks;
      (inter, List.rev !tracks)

let fix_track_end fd id inter at =
  prerr_endline (sprintf "Track #%d ends before %d" id at);
  let cat = ref (at - inter * gap_min_length) in
  try
    while !cat <= at do
      let x = track_info (read_raw_frame fd !cat) in
      if  x <> id then begin
	prerr_endline (sprintf "\t= %d" x);
	raise (Found_int (!cat - inter));
      end;
      cat := !cat + inter
    done; 
    prerr_endline "\tSTRANGE";
    -1
  with
    Found_int x -> 
      prerr_endline (sprintf "\t@ %d" x);
      x

let get_tracks fd reporter record =
  (* report *)
  let sectors = record.size / 2048 in
  let report_sector = 
    let rs = sectors / 100 in
    if rs = 0 then 1 else rs
  in
  reporter sectors 0;

  let all_tracks = ref [] in
  let sect = ref record.extent in
  
  try while true do
    prerr_endline "Fix Start blocks";
    let inter, tracks = fix_tracks_start fd !sect in
    prerr_endline "Search each track end";
    let alive_tracks = ref (List.length tracks) in
    let last_alive_sect = ref 0 in
    while !alive_tracks > 0 do
      for i = 0 to inter - 1 do
	begin
	  try
	    let track = List.assoc i tracks in
	    if track.tlength = -1 then begin
	      let x = track_info (read_raw_frame fd (!sect + i)) in
	      if x <> i then begin
		let end_sector = 
		  fix_track_end fd i inter (!sect + i) in
		track.tlength <- (end_sector - track.tstart) / inter + 1;
		if !last_alive_sect < end_sector then
		  last_alive_sect := end_sector;
		decr alive_tracks
	      end
	    end
	  with
	    Not_found -> ()
	end
      done;
      if !alive_tracks > 0 then
	sect := !sect + gap_min_length * inter;
      reporter sectors (!sect - record.extent)
    done;
    all_tracks := !all_tracks @ (List.map snd tracks);
(*    sect := !last_alive_sect + 1; *)
    prerr_endline (sprintf "Search Start blocks from %d (last alive %d)" !sect !last_alive_sect);
    let last_dead_sect = ref !sect in
    try
      while true do
	prerr_endline (sprintf "Search Start blocks at %d" !sect); 
	for i = 0 to 31 do
	  if !sect - record.extent > sectors then raise Exit;
	  if track_info (read_raw_frame fd !sect) <> -1 then
	    raise (Found_int !sect);
	  incr sect
	done;
	reporter sectors (!sect - record.extent);
	last_dead_sect := (!sect - 1);
	sect := !sect + track_min_length;
      done; raise Exit
    with
      Found_int s ->
	prerr_endline (sprintf "Start found near %d, should be after %d" s !last_dead_sect);
	sect := !last_dead_sect
  done; [] with Exit -> !all_tracks
;;  
*)

let get_tracks_from_path fd reporter path =
  get_tracks fd reporter (locate_file fd path)
