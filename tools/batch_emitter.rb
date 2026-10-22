# Breadth-first ("Execution::Next style") executor for gen_executor.rb, used
# when GQL_MODE=batch. Like graphql-ruby's Execution::Next, each field of a
# selection is resolved for all objects of that type at once, and the objects
# under it are gathered across parents and run as one batch. Unlike Next,
# every decision that depends only on the schema (how a field resolves, how
# its value completes, which values can be lazy) is made here, ahead of time.
#
# Null in a non-null position raises GQLBatchNull; gql_execute_doc then runs the
# query again on the depth-first executor, which reports the error with its path.
module BatchEmitter
  module_function

  # Code resolving field `field` of `obj` for object number `i`.
  def resolve_expr(field, rcls, call_args)
    hk = (field.hash_key.is_a?(Symbol) || field.hash_key.is_a?(String)) ? field.hash_key.to_sym : nil
    if hk
      "objs[i][#{hk.inspect}]"
    elsif rcls && user_method?(field.owner, field.resolver_method)
      "insts[i].#{field.resolver_method}#{call_args}"
    else
      "objs[i].#{field.method_sym}#{call_args}"
    end
  end

  def sync(v, lines, ind)
    LAZY.each do |klass, meth|
      lines << "#{ind}while #{v}.is_a?(#{klass})"
      lines << "#{ind}  #{v} = #{v}.#{meth}"
      lines << "#{ind}end"
    end
  end

  # Gather the objects under an object (or list of objects) field, run them
  # as one batch, then put each result back under its parent.
  def emit_composite(field, lines, ind)
    t = field.type
    nonnull = t.non_null?
    inner = nonnull ? t.of_type : t
    child = rb_ident(field.type.unwrap.graphql_name)
    lines << "#{ind}cp = e.child"
    lines << "#{ind}if cp.nil?"
    lines << "#{ind}  cp = plan_#{child}(e.sub)"
    lines << "#{ind}  e.child = cp"
    lines << "#{ind}end"
    lines << "#{ind}kids = []"
    if inner.list?
      item_t = inner.of_type
      abort "#{field.graphql_name}: nested lists of objects are not supported in batch mode" if (item_t.non_null? ? item_t.of_type : item_t).list?
      item_nn = item_t.non_null?
      lines << "#{ind}lens = []"
      lines << "#{ind}i = 0"
      lines << "#{ind}while i < n"
      lines << "#{ind}  v = vals[i]"
      sync("v", lines, ind + "  ")
      lines << "#{ind}  if v.nil?"
      lines << "#{ind}    raise GQLBatchNull, \"#{field.graphql_name}\"" if nonnull
      lines << "#{ind}    lens << -1"
      lines << "#{ind}  else"
      lines << "#{ind}    j = 0"
      lines << "#{ind}    while j < v.size"
      lines << "#{ind}      item = v[j]"
      sync("item", lines, ind + "      ")
      lines << "#{ind}      raise GQLBatchNull, \"#{field.graphql_name} item\" if item.nil?" if item_nn
      lines << "#{ind}      kids << item"
      lines << "#{ind}      j += 1"
      lines << "#{ind}    end"
      lines << "#{ind}    lens << v.size"
      lines << "#{ind}  end"
      lines << "#{ind}  i += 1"
      lines << "#{ind}end"
      lines << "#{ind}kres = batch_#{child}(kids, cp)"
      lines << "#{ind}k = 0"
      lines << "#{ind}i = 0"
      lines << "#{ind}while i < n"
      lines << "#{ind}  len = lens[i]"
      lines << "#{ind}  if len < 0"
      lines << "#{ind}    res[i][key] = nil"
      lines << "#{ind}  else"
      lines << "#{ind}    arr = []"
      lines << "#{ind}    j = 0"
      lines << "#{ind}    while j < len"
      lines << "#{ind}      arr << kres[k]"
      lines << "#{ind}      k += 1"
      lines << "#{ind}      j += 1"
      lines << "#{ind}    end"
      lines << "#{ind}    res[i][key] = arr"
      lines << "#{ind}  end"
      lines << "#{ind}  i += 1"
      lines << "#{ind}end"
    else
      lines << "#{ind}has = []"
      lines << "#{ind}i = 0"
      lines << "#{ind}while i < n"
      lines << "#{ind}  v = vals[i]"
      sync("v", lines, ind + "  ")
      lines << "#{ind}  if v.nil?"
      lines << "#{ind}    raise GQLBatchNull, \"#{field.graphql_name}\"" if nonnull
      lines << "#{ind}    has << false"
      lines << "#{ind}  else"
      lines << "#{ind}    kids << v"
      lines << "#{ind}    has << true"
      lines << "#{ind}  end"
      lines << "#{ind}  i += 1"
      lines << "#{ind}end"
      lines << "#{ind}kres = batch_#{child}(kids, cp)"
      lines << "#{ind}k = 0"
      lines << "#{ind}i = 0"
      lines << "#{ind}while i < n"
      lines << "#{ind}  if has[i]"
      lines << "#{ind}    res[i][key] = kres[k]"
      lines << "#{ind}    k += 1"
      lines << "#{ind}  else"
      lines << "#{ind}    res[i][key] = nil"
      lines << "#{ind}  end"
      lines << "#{ind}  i += 1"
      lines << "#{ind}end"
    end
  end

  def source(objects, resolver_class, em, root)
    out = +"class GQLBatchNull < StandardError\nend\n\n"
    out << "# Breadth-first executor: one pass per field over all objects of a type.\n"
    out << "class GQLBatchExecutor < GQLExecutor\n"
    objects.each do |obj|
      tname = obj.graphql_name
      id = rb_ident(tname)
      rcls = resolver_class[obj]
      out << "  def batch_#{id}(objs, plan)\n    n = objs.size\n    res = []\n    i = 0\n"
      out << "    while i < n\n      res << {}\n      i += 1\n    end\n"
      if rcls
        out << "    insts = []\n    i = 0\n    while i < n\n      insts << #{rcls}.new(objs[i], @context)\n      i += 1\n    end\n"
      end
      out << "    e = plan.first\n    until e.nil?\n      key = e.key\n      case e.fid\n"
      out << "      when 0\n        i = 0\n        while i < n\n          res[i][key] = #{tname.inspect}\n          i += 1\n        end\n"
      obj.fields.each_value.with_index do |field, fi|
        lines = []
        ind = "        "
        # arguments are the same for every object of the batch: read them once
        lines << "#{ind}f = e.field"
        kwargs = []
        field.arguments.each_value do |arg|
          a = em.fresh("a")
          k = em.fresh("k_#{arg.keyword}_")
          lines << "#{ind}#{a} = find_arg(f, #{arg.graphql_name.inspect})"
          reader = arg_reader(arg.type, a)
          if arg.type.non_null? && arg.default_value?
            lines << "#{ind}#{k} = #{a}.nil? ? #{arg.default_value.inspect} : #{reader}"
          elsif arg.type.non_null?
            lines << "#{ind}#{k} = #{reader}"
          else
            dflt = arg.default_value? ? arg.default_value.inspect : "nil"
            lines << "#{ind}#{k} = #{a}.nil? ? #{dflt} : (arg_null?(#{a}) ? nil : #{reader})"
          end
          kwargs << "#{arg.keyword}: #{k}"
        end
        call_args = kwargs.empty? ? "" : "(#{kwargs.join(", ")})"
        # resolve the field for all objects
        lines << "#{ind}vals = []"
        lines << "#{ind}i = 0"
        lines << "#{ind}while i < n"
        lines << "#{ind}  vals << #{resolve_expr(field, rcls, call_args)}"
        lines << "#{ind}  i += 1"
        lines << "#{ind}end"
        # then complete them
        if field.type.unwrap.kind.object?
          emit_composite(field, lines, ind)
        else
          lines << "#{ind}i = 0"
          lines << "#{ind}while i < n"
          lines << "#{ind}  v = vals[i]"
          if ABLATE.include?("complete")
            # continue_value / continue_field: walk the type at run time, per value
            lines << "#{ind}  c = gql_complete_generic(#{GenericTypes.const(field.type)}, v, e)"
            lines << "#{ind}  raise GQLBatchNull, #{field.graphql_name.inspect} if GQL_PROP.equal?(c)"
            lines << "#{ind}  res[i][key] = c"
          else
            r = em.complete(field.type, "v", lines, ind + "  ", "raise GQLBatchNull, #{field.graphql_name.inspect}", "nil")
            lines << "#{ind}  res[i][key] = #{r}"
          end
          lines << "#{ind}  i += 1"
          lines << "#{ind}end"
        end
        out << "      when #{fi + 1}\n" << lines.join("\n") << "\n"
      end
      out << "      end\n      e = e.next_entry\n    end\n    res\n  end\n\n"
    end
    out << "end\n\n"
    out << <<~RUBY
      def gql_execute_doc(doc, variables, context)
        errors = GQLValidator.new(doc).validate
        return { "errors" => errors } unless errors.empty?
        op = doc.ops[0]
        begin
          bx = GQLBatchExecutor.new(doc, context)
          return { "errors" => bx.errors } unless bx.coerce_variables(op, variables)
          data = bx.batch_#{rb_ident(root)}([nil], bx.plan_#{rb_ident(root)}(op.sels))[0]
          return bx.errors.empty? ? { "data" => data } : { "errors" => bx.errors, "data" => data }
        rescue GQLBatchNull
          # a null in a non-null position: the depth-first executor reports it with its path
        end
        ex = GQLExecutor.new(doc, context)
        return { "errors" => ex.errors } unless ex.coerce_variables(op, variables)
        data = ex.exec_#{rb_ident(root)}(nil, ex.plan_#{rb_ident(root)}(op.sels))
        ex.errors.empty? ? { "data" => data } : { "errors" => ex.errors, "data" => data }
      end
    RUBY
    out
  end
end
