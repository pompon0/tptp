{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE LambdaCase #-}

-- |
-- Module       : Data.TPTP.Internal
-- Copyright    : (c) Evgenii Kotelnikov, 2019
-- License      : GPL-3
-- Maintainer   : evgeny.kotelnikov@gmail.com
-- Stability    : experimental
--

module Data.TPTP.Internal where

import Data.List (find)
import Data.Text (Text)

import Data.TPTP

-- $setup
-- >>> :set -XOverloadedStrings


-- * Names

-- | The class 'Named' allows assigning concrete names to reserved constants
-- in the TPTP language.
class Named a where
  name :: a -> Text

instance Named Function where
  name = \case
    Uminus     -> "uminus"
    Sum        -> "sum"
    Difference -> "difference"
    Product    -> "product"
    Quotient   -> "quotient"
    QuotientE  -> "quotient_e"
    QuotientT  -> "quotient_t"
    QuotientF  -> "quotient_f"
    RemainderE -> "remainder_e"
    RemainderT -> "remainder_t"
    RemainderF -> "remainder_f"
    Floor      -> "floor"
    Ceiling    -> "ceiling"
    Truncate   -> "truncate"
    Round      -> "round"
    ToInt      -> "to_int"
    ToRat      -> "to_rat"
    ToReal     -> "to_real"

instance Named Predicate where
  name = \case
    Tautology -> "true"
    Falsum    -> "false"
    Distinct  -> "distinct"
    Less      -> "less"
    Lesseq    -> "lesseq"
    Greater   -> "greater"
    Greatereq -> "greatereq"
    IsInt     -> "is_int"
    IsRat     -> "is_rat"

instance Named Sort where
  name = \case
    I    -> "i"
    O    -> "o"
    Int  -> "int"
    Real -> "real"
    Rat  -> "rat"

instance Named Sign where
  name = \case
    Positive -> "="
    Negative -> "!="

instance Named Quantifier where
  name = \case
    Forall -> "!"
    Exists -> "?"

instance Named Connective where
  name = \case
    Conjunction -> "&"
    Disjunction -> "|"
    Implication -> "=>"
    Equivalence -> "<=>"
    ExclusiveOr -> "<~>"
    NegatedConjunction  -> "~&"
    NegatedDisjunction  -> "~|"
    ReversedImplication -> "<="

-- | Check whether a given logical connective is associative or nor.
isAssociative :: Connective -> Bool
isAssociative = \case
  Conjunction -> True
  Disjunction -> True
  Implication -> False
  Equivalence -> False
  ExclusiveOr -> False
  NegatedConjunction  -> False
  NegatedDisjunction  -> False
  ReversedImplication -> False

instance Named Role where
  name = \case
    Axiom             -> "axiom"
    Hypothesis        -> "hypothesis"
    Definition        -> "definition"
    Assumption        -> "assumption"
    Lemma             -> "lemma"
    Theorem           -> "theorem"
    Corollary         -> "corollary"
    Conjecture        -> "conjecture"
    NegatedConjecture -> "negated_conjecture"
    Plain             -> "plain"
    FiDomain          -> "fi_domain"
    FiFunctors        -> "fi_functors"
    FiPredicates      -> "fi_predicates"
    Unknown           -> "unknown"

instance Named Intro where
  name = \case
    ByDefinition  -> "definition"
    AxiomOfChoice -> "axiom_of_choice"
    ByTautology   -> "tautology"
    ByAssumption  -> "assumption"

-- | A smart 'Extended' constructor - only uses 'Extended' if the given string
-- does not correspond to any of the standard identifiers.
--
-- >>> extended "int" :: Reserved Sort
-- Standard Int
--
-- >>> extended "array" :: Reserved Sort
-- Extended "array"
extended :: (Named a, Enum a, Bounded a) => Text -> Reserved a
extended t
  | Just a <- find (\a -> name a == t) [minBound..] = Standard a
  | otherwise = Extended t


-- * TPTP languages

-- | The language of logical formulas supported by TPTP.
data Language
  = CNF_ -- ^ The language of clausal normal forms of unsorted first-order logic.
  | FOF_ -- ^ The language of unsorted first-order logic.
  | TFF_ -- ^ The language of sorted first-order logic, both monomorphic (TFF0)
         -- and polymorphic (TFF1).
  deriving (Eq, Show, Ord, Enum, Bounded)

instance Named Language where
  name = \case
    CNF_ -> "cnf"
    FOF_ -> "fof"
    TFF_ -> "tff"

-- | The language of a given TPTP declaration.
language :: Declaration -> Language
language = \case
  Sort{}      -> TFF_
  Typing{}    -> TFF_
  Formula _ f -> formulaLanguage f

-- | The language of a given TPTP formula.
formulaLanguage :: Formula -> Language
formulaLanguage = \case
  CNF{}  -> CNF_
  FOF{}  -> FOF_
  TFF0{} -> TFF_
  TFF1{} -> TFF_
