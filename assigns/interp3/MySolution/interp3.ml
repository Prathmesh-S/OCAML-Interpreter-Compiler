#use "./../../../classlib/OCaml/MyOCaml.ml";;
#use "./interp2.ml";;

(*

Please implement the [compile] function following the
specifications described in CS320_Fall_2023_Project-3.pdf

Notes:
1. You are only allowed to use library functions defined in MyOCaml.ml
   or ones you implement yourself.
2. You may NOT use OCaml standard library functions directly.

*)

(* ------------------------------------------------------------ *)

(* abstract syntax tree of high-level language *)

type uopr =
  | Neg | Not

type bopr =
  | Add | Sub | Mul | Div | Mod
  | And | Or
  | Lt  | Gt  | Lte | Gte | Eq

type expr =
  | Int of int
  | Bool of bool
  | Unit
  | UOpr of uopr * expr
  | BOpr of bopr * expr * expr
  | Var of string
  | Fun of string * string * expr
  | App of expr * expr
  | Let of string * expr * expr
  | Seq of expr * expr
  | Ifte of expr * expr * expr
  | Trace of expr

(* ------------------------------------------------------------ *)

(* combinator for left-associative operators *)

let chain_left (p : 'a parser) (q : ('a -> 'a -> 'a) parser) : 'a parser =
  let* init = p in
  let* fms = many (let* f = q in let* m = p in pure (f, m)) in
  let m = list_foldleft fms init (fun acc (f, m) -> f acc m) in
  pure m

let rec chain_right (p : 'a parser) (q : ('a -> 'a -> 'a) parser) : 'a parser =
  let* m = p in
  (let* f = q in
   let* rest = chain_right p q in
   pure (f m rest)) <|> 
  (pure m)

let opt (p : 'a parser) : 'a option parser =
  (let* x = p in pure (Some x)) <|> pure None

(* basic constants *)

let parse_int : expr parser =
  let* n = natural in
  pure (Int n) << whitespaces

let parse_bool : expr parser =
  (keyword "true" >> pure (Bool true)) <|>
  (keyword "false" >> pure (Bool false))

let parse_unit : expr parser =
  keyword "(" >> keyword ")" >> pure Unit

(* names *)

let isReserved s =
  let reserved = 
    ["let"; "rec"; "in"; "fun"; "if"; "then"; "else"; "trace"; "mod"; "not"] 
  in
  list_exists reserved (fun s0 -> s0 = s)

let parse_name : string parser =
  let lower = satisfy char_islower in
  let upper = satisfy char_isupper in
  let digit = satisfy char_isdigit in
  let quote = char '\'' in
  let wildc = char '_' in
  let* c = lower <|> wildc in
  let* cs = many (lower <|> upper <|> digit <|> wildc <|> quote) in
  let s = string_make_fwork (list_foreach (c :: cs)) in
  if isReserved s then fail
  else pure s << whitespaces

(* unary operators *)

let parse_neg : (expr -> expr) parser =
  keyword "-" >> pure (fun m -> UOpr (Neg, m))

(* binary operators *)

let parse_add : (expr -> expr -> expr) parser =
  keyword "+" >> pure (fun m n -> BOpr (Add, m, n))

let parse_sub : (expr -> expr -> expr) parser =
  keyword "-" >> pure (fun m n -> BOpr (Sub, m, n))

let parse_mul : (expr -> expr -> expr) parser =
  keyword "*" >> pure (fun m n -> BOpr (Mul, m, n))

let parse_div : (expr -> expr -> expr) parser =
  keyword "/" >> pure (fun m n -> BOpr (Div, m, n))

let parse_mod : (expr -> expr -> expr) parser =
  keyword "mod" >> pure (fun m n -> BOpr (Mod, m, n))

let parse_and : (expr -> expr -> expr) parser =
  keyword "&&" >> pure (fun m n -> BOpr (And, m, n))

let parse_or : (expr -> expr -> expr) parser =
  keyword "||" >> pure (fun m n -> BOpr (Or, m, n))

let parse_lt : (expr -> expr -> expr) parser =
  keyword "<" >> pure (fun m n -> BOpr (Lt, m, n))

let parse_gt : (expr -> expr -> expr) parser =
  keyword ">" >> pure (fun m n -> BOpr (Gt, m, n))

let parse_lte : (expr -> expr -> expr) parser =
  keyword "<=" >> pure (fun m n -> BOpr (Lte, m, n))

let parse_gte : (expr -> expr -> expr) parser =
  keyword ">=" >> pure (fun m n -> BOpr (Gte, m, n))

let parse_eq : (expr -> expr -> expr) parser =
  keyword "=" >> pure (fun m n -> BOpr (Eq, m, n))

let parse_neq : (expr -> expr -> expr) parser =
  keyword "<>" >> pure (fun m n -> UOpr (Not, BOpr (Eq, m, n)))

let parse_seq : (expr -> expr -> expr) parser =
  keyword ";" >> pure (fun m n -> Seq (m, n))

(* expression parsing *)

let rec parse_expr () = 
  let* _ = pure () in
  parse_expr9 ()

and parse_expr1 () : expr parser = 
  let* _ = pure () in
  parse_int <|> 
  parse_bool <|> 
  parse_unit <|>
  parse_var () <|>
  parse_fun () <|>
  parse_letrec () <|>
  parse_let () <|>
  parse_ifte () <|>
  parse_trace () <|>
  parse_not () <|>
  (keyword "(" >> parse_expr () << keyword ")")

and parse_expr2 () : expr parser =
  let* m = parse_expr1 () in
  let* ms = many' parse_expr1 in
  let m = list_foldleft ms m (fun acc m -> App (acc, m)) in
  pure m

and parse_expr3 () : expr parser =
  let* f_opt = opt parse_neg in
  let* m = parse_expr2 () in
  match f_opt with
  | Some f -> pure (f m)
  | None -> pure m

and parse_expr4 () : expr parser =
  let opr = parse_mul <|> parse_div <|> parse_mod in
  chain_left (parse_expr3 ()) opr

and parse_expr5 () : expr parser =
  let opr = parse_add <|> parse_sub in
  chain_left (parse_expr4 ()) opr

and parse_expr6 () : expr parser =
  let opr = 
    parse_lte <|> 
    parse_gte <|>
    parse_neq <|>
    parse_lt <|> 
    parse_gt <|>
    parse_eq
  in
  chain_left (parse_expr5 ()) opr

and parse_expr7 () : expr parser =
  chain_left (parse_expr6 ()) parse_and

and parse_expr8 () : expr parser =
  chain_left (parse_expr7 ()) parse_or

and parse_expr9 () : expr parser =
  chain_right (parse_expr8 ()) parse_seq

and parse_var () : expr parser =
  let* x = parse_name in
  pure (Var x)

and parse_fun () : expr parser =
  let* _ = keyword "fun" in
  let* xs = many1 parse_name in 
  let* _ = keyword "->" in
  let* body = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure m

and parse_let () : expr parser =
  let* _ = keyword "let" in
  let* x = parse_name in
  let* xs = many parse_name in
  let* _ = keyword "=" in
  let* body = parse_expr () in
  let* _ = keyword "in" in
  let* n = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure (Let (x, m, n))

and parse_letrec () : expr parser =
  let* _ = keyword "let" in
  let* _ = keyword "rec" in
  let* f = parse_name in
  let* x = parse_name in
  let* xs = many parse_name in
  let* _ = keyword "=" in
  let* body = parse_expr () in
  let* _ = keyword "in" in
  let* n = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure (Let (f, Fun (f, x, m), n))

and parse_ifte () : expr parser =
  let* _ = keyword "if" in
  let* m = parse_expr () in
  let* _ = keyword "then" in
  let* n1 = parse_expr () in
  let* _ = keyword "else" in
  let* n2 = parse_expr () in
  pure (Ifte (m, n1, n2))

and parse_trace () : expr parser =
  let* _ = keyword "trace" in
  let* m = parse_expr1 () in
  pure (Trace m) 

and parse_not () : expr parser =
  let* _ = keyword "not" in
  let* m = parse_expr1 () in
  pure (UOpr (Not, m))

exception SyntaxError
exception UnboundVariable of string

type scope = (string * string) list

let new_var =
  let stamp = ref 0 in
  fun x ->
    incr stamp;
    let xvar = string_filter x (fun c -> c <> '_' && c <> '\'') in
    string_concat_list ["v"; xvar; "i"; string_of_int !stamp]

let find_var scope s =
  let rec loop scope =
    match scope with
    | [] -> None
    | (s0, x) :: scope ->
      if s = s0 then Some x
      else loop scope
  in loop scope

let scope_expr (m : expr) : expr = 
  let rec aux scope m =
    match m with
    | Int i -> Int i
    | Bool b -> Bool b
    | Unit -> Unit
    | UOpr (opr, m) -> UOpr (opr, aux scope m)
    | BOpr (opr, m, n) -> 
      let m = aux scope m in
      let n = aux scope n in
      BOpr (opr, m, n)
    | Var s -> 
      (match find_var scope s with
       | None -> raise (UnboundVariable s)
       | Some x -> Var x)
    | Fun (f, x, m) -> 
      let fvar = new_var f in
      let xvar = new_var x in
      let m = aux ((f, fvar) :: (x, xvar) :: scope) m in
      Fun (fvar, xvar, m)
    | App (m, n) ->
      let m = aux scope m in
      let n = aux scope n in
      App (m, n)
    | Let (x, m, n) ->
      let xvar = new_var x in
      let m = aux scope m in
      let n = aux ((x, xvar) :: scope) n in
      Let (xvar, m, n)
    | Seq (m, n) ->
      let m = aux scope m in
      let n = aux scope n in
      Seq (m, n)
    | Ifte (m, n1, n2) ->
      let m = aux scope m in
      let n1 = aux scope n1 in
      let n2 = aux scope n2 in
      Ifte (m, n1, n2)
    | Trace m -> Trace (aux scope m)
  in
  aux [] m

(* ------------------------------------------------------------ *)

(* parser for the high-level language *)

let parse_prog (s : string) : expr =
  match string_parse (whitespaces >> parse_expr ()) s with
  | Some (m, []) -> scope_expr m
  | _ -> raise SyntaxError


  (*The code below is mine*)

(*Int to String Function*)
let rec
nat2str(n0: int): string =
if n0 < 10 then str(chr(n0+48))
else string_snoc(nat2str(n0/10))(chr(n0 mod 10 + 48))

(*Bool to String Functions*)

let boolToString(x:bool):string = 
match x with
  | true -> "True"
  | false -> "False"

let
int2str(n0: int): string =
if n0 >= 0 then nat2str(n0) else string_cons('-')(nat2str(-n0))
;;


(*
let compile (s : string) : string = 
  match string_parse (whitespaces >> parse_expr ()) s with
  | Some (m, []) -> match scope_expr m with 
                      |Int x -> "Push " ^ int2str (x) ^ ";"
                      |Bool x -> "Push " ^ boolToString (x) ^ ";" (*Works with lowercase true/false*)
                      |Unit -> "Push Unit" ^ ";"
                      |Fun(a,b,c) -> "Push " ^ a ^ "; Push " ^ b  ^ ";" (*Fix This*)
                      |UOpr(Neg, Int a) -> "Push " ^ int2str a ^ "; Push -1; Mul" ^ ";"
                      |UOpr(Neg, anExpression) -> "-" ^ compile (anExpression)
  | _ -> raise SyntaxError
;;
*)

let alltoString(x:coms) = 
  "yeah"
;;

let rec const_to_string (c: const) =
  match c with
  | Int i -> int2str i
  | Bool b -> boolToString b
  | Unit -> "unit"
  | Sym s -> s

and value_to_string v =
  match v with
  | VInt i -> int2str i
  | VBool b -> boolToString b
  | VUnit -> "unit"
  | VSym s -> s
  | VClo (param, _, coms) -> "fun " ^ param ^ " -> " ^ (toString coms)

and com_to_string c =
  match c with
  | Push con -> "Push " ^ (const_to_string con)
  | Pop -> "Pop"
  | Swap -> "Swap"
  | Trace1 -> "Trace"
  | Add -> "Add"
  | Sub -> "Sub"
  | Mul -> "Mul"
  | Div -> "Div"
  | And -> "And"
  | Or -> "Or"
  | Not -> "Not"
  | Lt -> "Lt"
  | Gt -> "Gt"
  | IfThenElse (c1, c2) -> "If " ^ (toString c1) ^ " Else " ^ (toString c2) ^ " End"
  | Bind -> "Bind"
  | Lookup -> "Lookup"
  | Fun c -> "Fun " ^ (toString c) ^ " End"
  | Call -> "Call"
  | Ret -> "Return"

and coms_to_string coms =
  let rec coms_to_string_acc acc coms =
    match coms with
    | [] -> acc
    | [c] -> acc ^ com_to_string c
    | c :: rest -> coms_to_string_acc (acc ^ com_to_string c ^ "; ") rest
  in
   (coms_to_string_acc "" coms)

and toString coms =
  (coms_to_string coms) ^ ";"
;;

let rec compile1 (tree: expr) : coms = 
  match tree with 
            |Int x -> [Push (Int x);]
            |Bool x -> [Push (Bool x);]
            |Unit -> [Push (Unit);]
            |Var x -> [Push (Sym x);Lookup;]
            |UOpr(Neg, expression) -> compile1 expression @ [Push (Int (-1)); Mul;]
            |UOpr(Not, expression) -> compile1 expression @ [Not;]
            |BOpr(Add, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Add;]
            |BOpr(Sub, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Sub;]
            |BOpr(Mul, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Mul;]
            |BOpr(Div, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Div;]
            |BOpr(Mod, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ compile1 expr1 @ compile1 expr2 @ [Swap;Div;Mul;Swap;Sub;]
            |BOpr(And, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [And;]
            |BOpr(Or, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Or;]
            |BOpr(Lt, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Lt;]
            |BOpr(Gt, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Gt;]
            |BOpr(Lte, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Gt;Not;]
            |BOpr(Gte, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Lt;Not;]
            |BOpr(Eq, expr1, expr2) -> compile1 expr1 @ compile1 expr2 @ [Swap;Lt;Not;] @ compile1 expr1 @ compile1 expr2 @ [Swap;Gt;Not;And]
            |Let (a, expr1, expr2) ->  compile1 expr1 @ [Push (Sym a);Bind;] @ compile1 expr2
            |Fun(a, b, expr) -> let arg = [Push (Sym b); Bind;] @ (compile1 expr) @ [Swap; Ret;] in [Push (Sym a); Fun (arg);] (*Or use Return*)
            |App(expr1, expr2) -> (compile1 expr1) @ (compile1 expr2) @ [Swap; Call;]
            |Seq(expr1, expr2) -> compile1 expr1 @ compile1 expr2
            |Ifte(expr1, expr2, expr3) -> compile1 expr1 @ [IfThenElse(compile1 expr2, compile1 expr3);]
            |Trace (expr1) -> compile1 expr1 @ [Trace1;Pop;]
;;

let compile (s : string) : string = 
  match string_parse (whitespaces >> parse_expr ()) s with
  | Some (m, []) -> let parseTree = (scope_expr m) in 
                        toString(compile1(parseTree))
  | _ -> raise SyntaxError
;;
