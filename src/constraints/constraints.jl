export CanonicalConstr, CvxConstr, ==, >=, <=, <, >, +

# TODO: Break down constraints.jl into multiple constraints: equality/exponential,
# SOCP, SDP etc constraints

# TODO: CVX constraint should be an abstract class and children should be stuff
# like CVXEqualityConstr. Read:
# http://docs.julialang.org/en/release-0.2/manual/performance-tips/#break-functions-into-multiple-definitions

type CanonicalConstr
  coeffs::VecOrMatOrSparse
  vars::Array{Int64, 1}
  constant::Value
  is_eq::Bool
  is_conic::Bool

  function CanonicalConstr(coeffs::VecOrMat, vars::Array{Int64, 1}, constant::Value, is_eq::Bool, is_conic::Bool)
    return new(coeffs, vars, constant, is_eq, is_conic)
  end

  function CanonicalConstr(coeffs::Number, vars::Array{Int64, 1}, constant::Value, is_eq::Bool, is_conic::Bool)
    return new([coeffs], vars, constant, is_eq, is_conic)
  end

  function CanonicalConstr(coeffs::VecOrMat, vars::Int64, constant::Value, is_eq::Bool, is_conic::Bool)
    return new(coeffs, [vars], constant, is_eq, is_conic)
  end

  function CanonicalConstr(coeffs::Number, vars::Int64, constant::Value, is_eq::Bool, is_conic::Bool)
    return new([coeffs], [vars], constant, is_eq, is_conic)
  end
end


type CvxConstr
  head
  lhs::AbstractCvxExpr
  rhs::AbstractCvxExpr
  vexity::Symbol
  dual_value
  canon_form::Function
  function CvxConstr(head::Symbol, lhs::AbstractCvxExpr, rhs::AbstractCvxExpr)
    # Check vexity
    if head == :(==)
      if lhs.vexity in (:linear, :constant)  && rhs.vexity in (:linear, :constant)
        vexity = :linear
      else
        error("equality constraints between nonlinear expressions are not DCP compliant")
      end
    elseif head == :(<=)
      if lhs.vexity in (:linear, :constant, :convex) && rhs.vexity in (:linear, :constant, :concave)
        vexity = :convex
      else
        # error("constraint is not DCP compliant")
        # TODO: Figure it out
        vexity = :convex
      end
    elseif head == :(>=)
      error(">= should have been transformed to <=")
    else
      error("unrecognized comparison $head")
    end

    canon_form = ()->
      begin
        if lhs.vexity == :constant && rhs.vexity == :constant
          error ("TODO")

        elseif rhs.vexity == :constant
          if rhs.size == (1, 1) && lhs.size != (1, 1)
            rhs = Constant(rhs.value * ones(lhs.size...), rhs.sign)
            coeffs = VecOrMatOrSparse[speye(get_vectorized_size(lhs))]
          elseif rhs.size != (1, 1) && lhs.size == (1, 1)
            coeffs = VecOrMatOrSparse[ones(get_vectorized_size(rhs), 1)]
          elseif lhs.size != rhs.size
            error("Can't compare expressions of size $(x.size) and $(y.size)")
          else
            coeffs = VecOrMatOrSparse[speye(get_vectorized_size(lhs))]
          end

          constant = typeof(rhs.value) <: Number ? rhs.value : vec(rhs.value)
          canon_constr = CanonicalConstr(coeffs, unique_id(lhs), constant, (head == :(==)), false)
          canon_constr_array = lhs.canon_form()
          push!(canon_constr_array, canon_constr)

        else
          if lhs.size == (1, 1) && rhs.size != (1, 1)
            sz = get_vectorized_size(rhs.size)
            coeffs = VecOrMatOrSparse[ones(sz, 1), -speye(sz)]
          elseif lhs.size != (1, 1) && rhs.size == (1, 1)
            sz = get_vectorized_size(lhs.size)
            coeffs = VecOrMatOrSparse[speye(sz), -ones(sz, 1)]
          elseif lhs.size != rhs.size
            error("Can't compare expressions of size $(x.size) and $(y.size)")
          else
            sz = get_vectorized_size(rhs.size)
            coeffs = VecOrMatOrSparse[speye(sz), -speye(sz)]
          end
          vars = [unique_id(lhs); unique_id(rhs)]
          constant = zeros(sz)

          canon_constr = CanonicalConstr(coeffs, vars, constant, (head == :(==)), false)
          canon_constr_array = lhs.canon_form()
          append!(canon_constr_array, rhs.canon_form())
          push!(canon_constr_array, canon_constr)
        end
        return canon_constr_array
      end

    return new(head, lhs, rhs, vexity, nothing, canon_form)
  end
end

==(x::AbstractCvxExpr, y::AbstractCvxExpr) = CvxConstr(:(==), x, y)
>=(x::AbstractCvxExpr, y::AbstractCvxExpr) = CvxConstr(:(<=), y, x)
<=(x::AbstractCvxExpr, y::AbstractCvxExpr) = CvxConstr(:(<=), x, y)
>(x::AbstractCvxExpr, y::AbstractCvxExpr) = >=(x, y)
<(x::AbstractCvxExpr, y::AbstractCvxExpr) = <=(x, y)

==(x::Constant, y::AbstractCvxExpr) = CvxConstr(:(==), y, x)
<=(x::Constant, y::AbstractCvxExpr) = CvxConstr(:(<=), -y, -x)
>=(x::Constant, y::AbstractCvxExpr) = CvxConstr(:(<=), y, x)
>(x::Constant, y::AbstractCvxExpr) = <=(y, x)
<(x::Constant, y::AbstractCvxExpr) = >=(y, x)

==(x::Value, y::AbstractCvxExpr) = CvxConstr(:(==), y, convert(CvxExpr, x))
>=(x::Value, y::AbstractCvxExpr) = CvxConstr(:(<=), y, convert(CvxExpr, x))
<=(x::Value, y::AbstractCvxExpr) = CvxConstr(:(<=), -y, -convert(CvxExpr, x))
>(x::Value, y::AbstractCvxExpr) = <=(y, x)
<(x::Value, y::AbstractCvxExpr) = >=(y, x)

==(x::AbstractCvxExpr, y::Value)= CvxConstr(:(==), x, convert(CvxExpr, y))
>=(x::AbstractCvxExpr, y::Value) = CvxConstr(:(<=), -x, -convert(CvxExpr, y))
<=(x::AbstractCvxExpr, y::Value) = CvxConstr(:(<=), x, convert(CvxExpr, y))
>(x::AbstractCvxExpr, y::Value) = >=(x, y)
<(x::AbstractCvxExpr, y::Value) = <=(x, y)

+(constraints::Array{CvxConstr}, new_constraint::CvxConstr) =
  push!(constraints, new_constraint)
+(constraints::Array{CvxConstr}, new_constraints::Array{CvxConstr}) =
  append!(constraints, new_constraints)
