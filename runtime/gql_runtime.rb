# Schema-independent runtime for generated GraphQL executors.
# Written for Spinel: plain classes, while loops, no metaprogramming.

V_VAR = 0
V_INT = 1
V_FLOAT = 2
V_STRING = 3
V_BOOL = 4
V_NULL = 5
V_ENUM = 6
V_LIST = 7
V_OBJECT = 8

S_FIELD = 0
S_SPREAD = 1
S_INLINE = 2

class GQLValue
  attr_accessor :kind, :str, :ival, :fval, :list, :obj_names, :obj_vals, :pos

  def initialize(kind, pos)
    @kind = kind
    @pos = pos
    @str = ""
    @ival = 0
    @fval = 0.0
    @list = []
    @obj_names = []
    @obj_vals = []
  end

  # GraphQL literal form, as graphql-ruby prints it in error messages.
  def to_graphql
    if @kind == V_VAR
      "$" + @str
    elsif @kind == V_INT
      @ival.to_s
    elsif @kind == V_FLOAT
      @fval.to_s
    elsif @kind == V_STRING
      @str.inspect
    elsif @kind == V_BOOL
      @ival == 1 ? "true" : "false"
    elsif @kind == V_NULL
      "null"
    elsif @kind == V_ENUM
      @str
    elsif @kind == V_LIST
      out = +"["
      i = 0
      while i < @list.size
        out << ", " if i > 0
        out << @list[i].to_graphql
        i += 1
      end
      out << "]"
      out
    else
      out = +"{"
      i = 0
      while i < @obj_names.size
        out << ", " if i > 0
        out << @obj_names[i] << ": " << @obj_vals[i].to_graphql
        i += 1
      end
      out << "}"
      out
    end
  end
end

class GQLArg
  attr_accessor :name, :value, :pos

  def initialize(name, value, pos)
    @name = name
    @value = value
    @pos = pos
  end
end

class GQLDirective
  attr_accessor :name, :args, :pos

  def initialize(name, args, pos)
    @name = name
    @args = args
    @pos = pos
  end
end

class GQLSel
  attr_accessor :kind, :name, :alias_name, :args, :directives, :sels, :type_cond, :pos

  def initialize(kind, pos)
    @kind = kind
    @pos = pos
    @name = ""
    @alias_name = ""
    @type_cond = ""
    @args = []
    @directives = []
    @sels = []
  end

  def response_key
    @alias_name == "" ? @name : @alias_name
  end
end

class GQLTypeRef
  attr_accessor :name, :non_null, :of

  def initialize(name, non_null, of)
    @name = name
    @non_null = non_null
    @of = of
  end

  def to_s
    base = @of.nil? ? @name : "[" + @of.to_s + "]"
    @non_null ? base + "!" : base
  end
end

class GQLVarDef
  attr_accessor :name, :type, :default, :pos

  def initialize(name, type, default, pos)
    @name = name
    @type = type
    @default = default
    @pos = pos
  end
end

class GQLOp
  attr_accessor :op_type, :name, :var_defs, :sels, :pos

  def initialize(op_type, name, pos)
    @op_type = op_type
    @name = name
    @pos = pos
    @var_defs = []
    @sels = []
  end
end

class GQLFragment
  attr_accessor :name, :type_cond, :sels, :pos

  def initialize(name, type_cond, pos)
    @name = name
    @type_cond = type_cond
    @pos = pos
    @sels = []
  end
end

class GQLDocument
  attr_accessor :ops, :fragments, :src

  def initialize(src)
    @src = src
    @ops = []
    @fragments = {}
  end
end

class GQLParseError < StandardError
  attr_reader :pos

  def initialize(msg, pos)
    super(msg)
    @pos = pos
  end
end

# Recursive-descent parser over bytes (no regexps, no token objects).
class GQLParser
  def initialize(src)
    @src = src
    @pos = 0
    @len = src.bytesize
  end

  def parse
    doc = GQLDocument.new(@src)
    while peek != -1
      b = peek
      if b == 123 # {
        op = GQLOp.new("query", "", @pos)
        op.sels = parse_selection_set
        doc.ops << op
      else
        start = @pos
        word = parse_name
        if word == "fragment"
          name = parse_name
          on = parse_name
          error("Expected 'on'", start) if on != "on"
          frag = GQLFragment.new(name, parse_name, start)
          parse_directives
          frag.sels = parse_selection_set
          doc.fragments[name] = frag
        elsif word == "query" || word == "mutation" || word == "subscription"
          name = name_start?(peek) ? parse_name : ""
          op = GQLOp.new(word, name, start)
          op.var_defs = parse_var_defs if peek == 40 # (
          parse_directives
          op.sels = parse_selection_set
          doc.ops << op
        else
          error("Unexpected name #{word}", start)
        end
      end
    end
    error("Unexpected end of document", @pos) if doc.ops.empty? && doc.fragments.empty?
    doc
  end

  def error(msg, pos)
    raise GQLParseError.new(msg, pos)
  end

  def skip_ignored
    while @pos < @len
      b = @src.getbyte(@pos)
      if b == 32 || b == 9 || b == 10 || b == 13 || b == 44
        @pos += 1
      elsif b == 35 # comment
        while @pos < @len && @src.getbyte(@pos) != 10 && @src.getbyte(@pos) != 13
          @pos += 1
        end
      else
        return
      end
    end
  end

  def peek
    skip_ignored
    @pos < @len ? @src.getbyte(@pos) : -1
  end

  def expect(b)
    if peek != b
      error("Expected #{b.chr}", @pos)
    end
    @pos += 1
  end

  def name_start?(b)
    (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95
  end

  def name_char?(b)
    (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95 || (b >= 48 && b <= 57)
  end

  def parse_name
    b = peek
    error("Expected a name", @pos) unless name_start?(b)
    start = @pos
    @pos += 1
    while @pos < @len && name_char?(@src.getbyte(@pos))
      @pos += 1
    end
    @src.byteslice(start, @pos - start)
  end

  def parse_selection_set
    expect(123)
    sels = []
    while peek != 125
      error("Unexpected end of document", @pos) if peek == -1
      sels << parse_selection
    end
    @pos += 1
    sels
  end

  def parse_selection
    start = @pos
    if peek == 46 # .
      if @pos + 2 < @len && @src.getbyte(@pos + 1) == 46 && @src.getbyte(@pos + 2) == 46
        @pos += 3
      else
        error("Expected ...", @pos)
      end
      if name_start?(peek)
        name_pos = @pos
        word = parse_name
        if word == "on"
          sel = GQLSel.new(S_INLINE, start)
          sel.type_cond = parse_name
          sel.directives = parse_directives
          sel.sels = parse_selection_set
          return sel
        end
        sel = GQLSel.new(S_SPREAD, start)
        sel.name = word
        sel.directives = parse_directives
        return sel
      end
      sel = GQLSel.new(S_INLINE, start)
      sel.directives = parse_directives
      sel.sels = parse_selection_set
      return sel
    end
    sel = GQLSel.new(S_FIELD, start)
    name = parse_name
    if peek == 58 # :
      @pos += 1
      sel.alias_name = name
      name = parse_name
    end
    sel.name = name
    sel.args = parse_arguments if peek == 40
    sel.directives = parse_directives
    sel.sels = parse_selection_set if peek == 123
    sel
  end

  def parse_arguments
    expect(40)
    args = []
    while peek != 41
      start = @pos
      name = parse_name
      expect(58)
      args << GQLArg.new(name, parse_value, start)
    end
    @pos += 1
    args
  end

  def parse_directives
    dirs = []
    while peek == 64 # @
      start = @pos
      @pos += 1
      name = parse_name
      args = peek == 40 ? parse_arguments : []
      dirs << GQLDirective.new(name, args, start)
    end
    dirs
  end

  def parse_var_defs
    expect(40)
    defs = []
    while peek != 41
      start = @pos
      expect(36) # $
      name = parse_name
      expect(58)
      type = parse_type
      default = nil
      if peek == 61 # =
        @pos += 1
        default = parse_value
      end
      parse_directives
      defs << GQLVarDef.new(name, type, default, start)
    end
    @pos += 1
    defs
  end

  def parse_type
    t = nil
    if peek == 91 # [
      @pos += 1
      inner = parse_type
      expect(93)
      t = GQLTypeRef.new("", false, inner)
    else
      t = GQLTypeRef.new(parse_name, false, nil)
    end
    if peek == 33 # !
      @pos += 1
      t.non_null = true
    end
    t
  end

  def parse_value
    b = peek
    start = @pos
    if b == 36 # $
      @pos += 1
      v = GQLValue.new(V_VAR, start)
      v.str = parse_name
      v
    elsif b == 34 # "
      v = GQLValue.new(V_STRING, start)
      v.str = parse_string
      v
    elsif b == 45 || (b >= 48 && b <= 57)
      parse_number
    elsif b == 91 # [
      @pos += 1
      v = GQLValue.new(V_LIST, start)
      while peek != 93
        error("Unexpected end of document", @pos) if peek == -1
        v.list << parse_value
      end
      @pos += 1
      v
    elsif b == 123 # {
      @pos += 1
      v = GQLValue.new(V_OBJECT, start)
      while peek != 125
        v.obj_names << parse_name
        expect(58)
        v.obj_vals << parse_value
      end
      @pos += 1
      v
    elsif name_start?(b)
      word = parse_name
      if word == "true" || word == "false"
        v = GQLValue.new(V_BOOL, start)
        v.ival = word == "true" ? 1 : 0
        v
      elsif word == "null"
        GQLValue.new(V_NULL, start)
      else
        v = GQLValue.new(V_ENUM, start)
        v.str = word
        v
      end
    else
      error("Expected a value", start)
      GQLValue.new(V_NULL, start)
    end
  end

  def parse_number
    start = @pos
    is_float = false
    @pos += 1 if @src.getbyte(@pos) == 45
    while @pos < @len && digit?(@src.getbyte(@pos))
      @pos += 1
    end
    if @pos < @len && @src.getbyte(@pos) == 46
      is_float = true
      @pos += 1
      while @pos < @len && digit?(@src.getbyte(@pos))
        @pos += 1
      end
    end
    if @pos < @len && (@src.getbyte(@pos) == 101 || @src.getbyte(@pos) == 69)
      is_float = true
      @pos += 1
      @pos += 1 if @pos < @len && (@src.getbyte(@pos) == 43 || @src.getbyte(@pos) == 45)
      while @pos < @len && digit?(@src.getbyte(@pos))
        @pos += 1
      end
    end
    text = @src.byteslice(start, @pos - start)
    if is_float
      v = GQLValue.new(V_FLOAT, start)
      v.fval = text.to_f
      v
    else
      v = GQLValue.new(V_INT, start)
      v.ival = text.to_i
      v
    end
  end

  def digit?(b)
    b >= 48 && b <= 57
  end

  def parse_string
    @pos += 1
    out = +""
    seg = @pos
    while true
      error("Unterminated string", @pos) if @pos >= @len
      b = @src.getbyte(@pos)
      if b == 34
        out << @src.byteslice(seg, @pos - seg)
        @pos += 1
        return out
      elsif b == 10 || b == 13
        error("Unterminated string", @pos)
      elsif b == 92 # backslash
        out << @src.byteslice(seg, @pos - seg)
        @pos += 1
        e = @src.getbyte(@pos)
        if e == 110
          out << "\n"
        elsif e == 116
          out << "\t"
        elsif e == 114
          out << "\r"
        elsif e == 98
          out << "\b"
        elsif e == 102
          out << "\f"
        elsif e == 117
          out << @src.byteslice(@pos + 1, 4).to_i(16).chr(Encoding::UTF_8)
          @pos += 4
        else
          out << e.chr
        end
        @pos += 1
        seg = @pos
      else
        @pos += 1
      end
    end
  end
end

# Line/column (1-based) of a byte offset.
def gql_location(src, pos)
  line = 1
  col = 1
  i = 0
  while i < pos
    if src.getbyte(i) == 10
      line += 1
      col = 1
    else
      col += 1
    end
    i += 1
  end
  { "line" => line, "column" => col }
end

# Strip list/non-null wrappers from a printed type ref ("[Post!]!" -> "Post").
def gql_unwrap(type_str)
  s = 0
  e = type_str.bytesize
  while s < e && type_str.getbyte(s) == 91
    s += 1
  end
  while e > s && (type_str.getbyte(e - 1) == 93 || type_str.getbyte(e - 1) == 33)
    e -= 1
  end
  type_str.byteslice(s, e - s)
end

# Static validation (subset of graphql-ruby's rules, same messages).
# Schema knowledge comes from generated functions: schema_field_type,
# schema_field_args, schema_arg_type, schema_arg_has_default, schema_type_kind,
# schema_enum_has, schema_root_type.
class GQLValidator
  def initialize(doc)
    @doc = doc
    @errors = []
    @op_label = ""
    @declared = {}
    @used_vars = {}
    @used_frags = {}
  end

  def validate
    i = 0
    while i < @doc.ops.size
      op = @doc.ops[i]
      @op_label = op.name == "" ? "anonymous " + op.op_type : op.name
      @declared = {}
      @used_vars = {}
      j = 0
      while j < op.var_defs.size
        @declared[op.var_defs[j].name] = true
        j += 1
      end
      path = [op.name == "" ? op.op_type : op.op_type + " " + op.name]
      validate_sels(schema_root_type(op.op_type), op.sels, path)
      j = 0
      while j < op.var_defs.size
        vd = op.var_defs[j]
        unless @used_vars.key?(vd.name)
          add("Variable $#{vd.name} is declared by #{@op_label} but not used", vd.pos, path,
              { "code" => "variableNotUsed", "variableName" => vd.name })
        end
        j += 1
      end
      i += 1
    end
    names = @doc.fragments.keys
    i = 0
    while i < names.size
      frag = @doc.fragments[names[i]]
      path = ["fragment " + frag.name]
      if schema_type_kind(frag.type_cond) == ""
        add("No such type #{frag.type_cond}, so it can't be a fragment condition", frag.pos, path,
            { "code" => "undefinedType", "typeName" => frag.type_cond })
      else
        validate_sels(frag.type_cond, frag.sels, path)
      end
      unless @used_frags.key?(frag.name)
        add("Fragment #{frag.name} was defined, but not used", frag.pos, path,
            { "code" => "useAndDefineFragment", "fragmentName" => frag.name })
      end
      i += 1
    end
    @errors
  end

  def add(message, pos, path, extensions)
    @errors << { "message" => message, "locations" => [gql_location(@doc.src, pos)], "path" => path,
                 "extensions" => extensions }
  end

  def validate_sels(parent, sels, path)
    i = 0
    while i < sels.size
      sel = sels[i]
      if sel.kind == S_FIELD
        validate_field(parent, sel, path)
      elsif sel.kind == S_SPREAD
        @used_frags[sel.name] = true
        unless @doc.fragments.key?(sel.name)
          add("Fragment #{sel.name} was used, but not defined", sel.pos, path + ["... " + sel.name],
              { "code" => "useAndDefineFragment", "fragmentName" => sel.name })
        end
        check_directive_vars(sel.directives, path)
      else
        cond = sel.type_cond == "" ? parent : sel.type_cond
        label = sel.type_cond == "" ? "..." : "... on " + sel.type_cond
        check_directive_vars(sel.directives, path)
        if schema_type_kind(cond) == ""
          add("No such type #{cond}, so it can't be a fragment condition", sel.pos, path + [label],
              { "code" => "undefinedType", "typeName" => cond })
        else
          validate_sels(cond, sel.sels, path + [label])
        end
      end
      i += 1
    end
  end

  def check_directive_vars(dirs, path)
    i = 0
    while i < dirs.size
      args = dirs[i].args
      j = 0
      while j < args.size
        check_var(args[j].value, path + [args[j].name])
        j += 1
      end
      i += 1
    end
  end

  def check_var(value, path)
    if value.kind == V_VAR
      @used_vars[value.str] = true
      unless @declared.key?(value.str)
        add("Variable $#{value.str} is used by #{@op_label} but not declared", value.pos, path,
            { "code" => "variableNotDefined", "variableName" => value.str })
      end
    elsif value.kind == V_LIST
      i = 0
      while i < value.list.size
        check_var(value.list[i], path)
        i += 1
      end
    end
  end

  def validate_field(parent, sel, path)
    key = sel.response_key
    fpath = path + [key]
    check_directive_vars(sel.directives, path)
    if sel.name == "__typename"
      return
    end
    type = schema_field_type(parent, sel.name)
    if type == ""
      add("Field '#{sel.name}' doesn't exist on type '#{parent}'", sel.pos, fpath,
          { "code" => "undefinedField", "typeName" => parent, "fieldName" => sel.name })
      return
    end
    accepted = schema_field_args(parent, sel.name)
    provided = {}
    i = 0
    while i < sel.args.size
      arg = sel.args[i]
      provided[arg.name] = true
      if accepted.include?(arg.name)
        check_var(arg.value, fpath + [arg.name])
        arg_type = schema_arg_type(parent, sel.name, arg.name)
        unless literal_ok?(arg_type, arg.value)
          add("Argument '#{arg.name}' on Field '#{sel.name}' has an invalid value (#{arg.value.to_graphql}). Expected type '#{arg_type}'.",
              sel.pos, fpath + [arg.name],
              { "code" => "argumentLiteralsIncompatible", "typeName" => "Field", "argumentName" => arg.name })
        end
      else
        add("Field '#{sel.name}' doesn't accept argument '#{arg.name}'", arg.pos, fpath + [arg.name],
            { "code" => "argumentNotAccepted", "name" => sel.name, "typeName" => "Field", "argumentName" => arg.name })
      end
      i += 1
    end
    missing = []
    i = 0
    while i < accepted.size
      a = accepted[i]
      t = schema_arg_type(parent, sel.name, a)
      if !provided.key?(a) && t.end_with?("!") && !schema_arg_has_default(parent, sel.name, a)
        missing << a
      end
      i += 1
    end
    unless missing.empty?
      add("Field '#{sel.name}' is missing required arguments: #{missing.join(", ")}", sel.pos, fpath,
          { "code" => "missingRequiredArguments", "className" => "Field", "name" => sel.name, "arguments" => missing.join(", ") })
    end
    base = gql_unwrap(type)
    kind = schema_type_kind(base)
    if kind == "OBJECT"
      if sel.sels.empty?
        add("Field must have selections (field '#{sel.name}' returns #{base} but has no selections. Did you mean '#{sel.name} { ... }'?)",
            sel.pos, fpath, { "code" => "selectionMismatch", "nodeName" => "field '#{sel.name}'", "typeName" => base })
      else
        validate_sels(base, sel.sels, fpath)
      end
    elsif !sel.sels.empty?
      names = +"["
      i = 0
      while i < sel.sels.size
        names << ", " if i > 0
        names << sel.sels[i].name.inspect
        i += 1
      end
      names << "]"
      what = kind == "ENUM" ? "enums" : "scalars"
      add("Selections can't be made on #{what} (field '#{sel.name}' returns #{base} but has selections #{names})",
          sel.pos, fpath, { "code" => "selectionMismatch", "nodeName" => "field '#{sel.name}'", "typeName" => base })
    end
  end

  def literal_ok?(type, value)
    if value.kind == V_VAR
      return true
    end
    if type.end_with?("!")
      return false if value.kind == V_NULL
      return literal_ok?(type.byteslice(0, type.bytesize - 1), value)
    end
    return true if value.kind == V_NULL
    if type.start_with?("[")
      inner = type.byteslice(1, type.bytesize - 2)
      if value.kind == V_LIST
        i = 0
        while i < value.list.size
          return false unless literal_ok?(inner, value.list[i])
          i += 1
        end
        return true
      end
      return literal_ok?(inner, value)
    end
    if type == "Int"
      value.kind == V_INT && value.ival >= -2147483648 && value.ival <= 2147483647
    elsif type == "Float"
      value.kind == V_INT || value.kind == V_FLOAT
    elsif type == "String"
      value.kind == V_STRING
    elsif type == "Boolean"
      value.kind == V_BOOL
    elsif type == "ID"
      value.kind == V_STRING || value.kind == V_INT
    elsif schema_type_kind(type) == "ENUM"
      value.kind == V_ENUM && schema_enum_has(type, value.str)
    else
      false
    end
  end
end

# Field plan for one selection set on one object type: fragments expanded,
# fields grouped by response key, field names resolved to integer ids.
# Child plans are built on first use and reused for every object.
# A linked list rather than arrays: Spinel stores arrays of objects untyped,
# while object-typed ivars stay typed.
class GQLPlanEntry
  attr_accessor :key, :fid, :field, :sub, :child, :next_entry

  def initialize(key, fid, field, sub)
    @key = key
    @fid = fid
    @field = field
    @sub = sub
    @child = nil
    @next_entry = nil
  end
end

class GQLPlan
  attr_reader :first

  def initialize
    @first = nil
    @last = nil
  end

  def add(key, fid, field, sub)
    e = GQLPlanEntry.new(key, fid, field, sub)
    if @last.nil?
      @first = e
    else
      @last.next_entry = e
    end
    @last = e
  end
end

# Base class for generated executors: field collection, variables, errors.
class GQLExecutorBase
  attr_reader :errors

  def initialize(doc, context)
    @doc = doc
    @context = context
    @errors = []
    @path = []
    @invalid = false
    @int_vars = {}
    @float_vars = {}
    @str_vars = {}
    @bool_vars = {}
    @null_vars = {}
  end

  # Coerce provided variables by their declared types; returns false on error.
  def coerce_variables(op, provided)
    ok = true
    i = 0
    while i < op.var_defs.size
      vd = op.var_defs[i]
      name = vd.name
      base = vd.type.name
      if provided.key?(name)
        x = provided[name]
        if x.nil?
          if vd.type.non_null
            var_error(vd, "null", "Expected value to not be null")
            ok = false
          end
          @null_vars[name] = true
        elsif !vd.type.of.nil?
          var_error(vd, x.inspect, "List variables are not supported by this executor")
          ok = false
        elsif base == "Int" && x.is_a?(Integer)
          @int_vars[name] = x.to_i
        elsif base == "Float" && (x.is_a?(Integer) || x.is_a?(Float))
          @float_vars[name] = x.to_f
        elsif (base == "ID" && (x.is_a?(String) || x.is_a?(Integer))) || (base == "String" && x.is_a?(String))
          @str_vars[name] = x.to_s
        elsif base == "Boolean" && (x == true || x == false)
          @bool_vars[name] = x == true
        elsif schema_type_kind(base) == "ENUM" && x.is_a?(String) && schema_enum_has(base, x.to_s)
          @str_vars[name] = x.to_s
        else
          var_error(vd, x.inspect, "Could not coerce value #{x.inspect} to #{base}")
          ok = false
        end
      elsif !vd.default.nil?
        store_literal(name, base, vd.default)
      elsif vd.type.non_null
        var_error(vd, "null", "Expected value to not be null")
        ok = false
      else
        @null_vars[name] = true
      end
      i += 1
    end
    ok
  end

  def store_literal(name, base, v)
    if v.kind == V_NULL
      @null_vars[name] = true
    elsif base == "Int"
      @int_vars[name] = v.ival
    elsif base == "Float"
      @float_vars[name] = v.kind == V_INT ? v.ival.to_f : v.fval
    elsif base == "Boolean"
      @bool_vars[name] = v.ival == 1
    elsif v.kind == V_INT
      @str_vars[name] = v.ival.to_s
    else
      @str_vars[name] = v.str
    end
  end

  def var_error(vd, value, explanation)
    @errors << { "message" => "Variable $#{vd.name} of type #{vd.type} was provided invalid value",
                 "locations" => [gql_location(@doc.src, vd.pos)],
                 "extensions" => { "value" => value, "problems" => [{ "path" => [], "explanation" => explanation }] } }
  end

  def var_null?(name)
    @null_vars.key?(name)
  end

  def find_arg(sel, name)
    i = 0
    while i < sel.args.size
      return sel.args[i].value if sel.args[i].name == name
      i += 1
    end
    nil
  end

  # Typed argument readers: literal or variable.
  def arg_int(v)
    v.kind == V_VAR ? @int_vars[v.str] : v.ival
  end

  def arg_float(v)
    if v.kind == V_VAR
      @float_vars[v.str]
    elsif v.kind == V_INT
      v.ival.to_f
    else
      v.fval
    end
  end

  def arg_str(v)
    if v.kind == V_VAR
      @str_vars[v.str]
    elsif v.kind == V_INT
      v.ival.to_s
    else
      v.str
    end
  end

  def arg_bool(v)
    v.kind == V_VAR ? @bool_vars[v.str] : v.ival == 1
  end

  # True when an argument is absent or explicitly null.
  def arg_null?(v)
    v.nil? || v.kind == V_NULL || (v.kind == V_VAR && var_null?(v.str))
  end

  def skip?(dirs)
    i = 0
    while i < dirs.size
      d = dirs[i]
      if d.name == "skip" || d.name == "include"
        cond = find_if(d)
        return true if d.name == "skip" && cond
        return true if d.name == "include" && !cond
      end
      i += 1
    end
    false
  end

  def find_if(d)
    i = 0
    while i < d.args.size
      return arg_bool(d.args[i].value) if d.args[i].name == "if"
      i += 1
    end
    false
  end

  # Group fields by response key, expanding fragments that apply to type_name.
  def collect_fields(type_name, sels, groups)
    i = 0
    while i < sels.size
      sel = sels[i]
      if sel.directives.empty? || !skip?(sel.directives)
        if sel.kind == S_FIELD
          key = sel.response_key
          if groups.key?(key)
            groups[key] << sel
          else
            groups[key] = [sel]
          end
        elsif sel.kind == S_INLINE
          if sel.type_cond == "" || type_applies?(sel.type_cond, type_name)
            collect_fields(type_name, sel.sels, groups)
          end
        else
          frag = @doc.fragments[sel.name]
          if type_applies?(frag.type_cond, type_name)
            collect_fields(type_name, frag.sels, groups)
          end
        end
      end
      i += 1
    end
  end

  def merged_sels(fs)
    return fs[0].sels if fs.size == 1
    out = []
    i = 0
    while i < fs.size
      out.concat(fs[i].sels)
      i += 1
    end
    out
  end

  def null_error(parent, field, sel)
    @errors << { "message" => "Cannot return null for non-nullable field #{parent}.#{field}",
                 "locations" => [gql_location(@doc.src, sel.pos)], "path" => @path.dup }
  end

  # Leaf fields do not push their key onto @path; add it here.
  def leaf_null_error(parent, field, sel, key)
    path = @path.dup
    path << key
    @errors << { "message" => "Cannot return null for non-nullable field #{parent}.#{field}",
                 "locations" => [gql_location(@doc.src, sel.pos)], "path" => path }
  end

  def null_element_error(parent, field, type, sel)
    @errors << { "message" => "Cannot return null for non-nullable element of type '#{type}' for #{parent}.#{field}",
                 "locations" => [gql_location(@doc.src, sel.pos)], "path" => @path.dup }
  end
end

def gql_parse_error_result(src, e)
  { "errors" => [{ "message" => e.message, "locations" => [gql_location(src, e.pos)] }] }
end

# Result coercion with graphql-ruby's checks (GQL_STRICT=1 executors):
# Int must fit in 32 bits (Types::Int.coerce_result), String must be UTF-8 or
# ASCII-only and is re-encoded otherwise (Types::String.coerce_result).
def gql_int_out(v)
  i = v.to_i
  raise "Int cannot represent non 32-bit signed integer value: #{i}" if i < -2147483648 || i > 2147483647
  i
end

def gql_str_out(v)
  s = v.to_s
  return s if s.encoding == Encoding::UTF_8 || s.ascii_only?
  s.encode(Encoding::UTF_8)
end
