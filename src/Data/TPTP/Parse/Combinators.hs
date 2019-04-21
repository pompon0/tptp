{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- |
-- Module       : Data.TPTP.Parse.Combinators
-- Description  : Parser combinators for the TPTP language.
-- Copyright    : (c) Evgenii Kotelnikov, 2019
-- License      : GPL-3
-- Maintainer   : evgeny.kotelnikov@gmail.com
-- Stability    : experimental
--

module Data.TPTP.Parse.Combinators (
  -- * Whitespace
  whitespace,

  -- * Names
  atom,
  var,
  distinctObject,
  function,
  predicate,

  -- * Sorts and types
  sort,
  tff1Sort,
  type_,

  -- * First-order logic
  number,
  term,
  literal,
  clause,
  unsortedFirstOrder,
  sortedFirstOrder,
  monomorphicFirstOrder,
  polymorphicFirstOrder,

  -- * Units
  unit,
  derivation,

  -- * Annotations
  intro,
  info,
  generalData,
  generalTerm,
  generalList,
  parent,
  source
) where

import Control.Applicative ((<|>), optional)

import Data.Attoparsec.Text as A hiding (Number, number)
import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit, isPrint)
import Data.Functor (($>))
import qualified Data.List as L
import qualified Data.List.NonEmpty as NEL

import qualified Data.Scientific as Sci

import Data.Text (Text)
import qualified Data.Text as T

import Data.TPTP
import Data.TPTP.Internal hiding (name)
import qualified Data.TPTP.Internal as I

-- * Helper functions

-- | Consume a single line comment - characters between @%@ and newline.
comment :: Parser ()
comment = char '%' *> skipWhile (not . isEndOfLine)
                   *> (endOfLine <|> endOfInput)
                  <?> "comment"

-- | Consume white space and trailing comments.
whitespace :: Parser ()
whitespace = skipSpace *> skipMany (comment *> skipSpace) <?> "whitespace"

-- | 'lexem' makes a given parser consume trailing whitespace. This function is
-- needed because off-the-shelf attoparsec parsers do not do it.
lexem :: Parser a -> Parser a
lexem p = p <* whitespace
{-# INLINE lexem #-}

-- | Parse an unsigned integer.
integer :: Parser Integer
integer = lexem decimal <?> "integer"
{-# INLINE integer #-}

token :: Text -> Parser Text
token t = lexem (string t) <?> "token " ++ T.unpack t
{-# INLINE token #-}

op :: Char -> Parser Char
op c = lexem (char c) <?> "operator " ++ [c]
{-# INLINE op #-}

parens :: Parser a -> Parser a
parens p = op '(' *> p <* op ')' <?> "parens"
{-# INLINE parens #-}

optionalParens :: Parser a -> Parser a
optionalParens p = parens p <|> p
{-# INLINE optionalParens #-}

brackets :: Parser a -> Parser a
brackets p = op '[' *> p <* op ']' <?> "brackets"
{-# INLINE brackets #-}

enum :: (Named a, Enum a, Bounded a) => Parser a
enum = choice
     $ fmap (\(n, c) -> token n $> c <?> "reserved " ++ T.unpack n)
     $ L.sortBy (\(a, _) (b, _) -> b `compare` a)
     $ fmap (\c -> (I.name c, c)) [minBound..]

name :: (Named a, Enum a, Bounded a) => Parser (Name a)
name =  Reserved <$> (char '$' *> enum)
    <|> Defined  <$> atom

keyword :: (Named a, Enum a, Bounded a) => Parser (Name a)
keyword =  Reserved <$> enum
       <|> Defined  <$> atom

isAlphaNumeric :: Char -> Bool
isAlphaNumeric c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'

isAsciiPrint :: Char -> Bool
isAsciiPrint c = isAscii c && isPrint c

maybeP :: Parser a -> Parser (Maybe a)
maybeP p = optional (op ',' *> p)


-- * Parser combinators

-- ** Names

lowerWord, upperWord :: Parser Text
lowerWord = T.cons <$> A.satisfy isAsciiLower <*> A.takeWhile isAlphaNumeric
upperWord = T.cons <$> A.satisfy isAsciiUpper <*> A.takeWhile isAlphaNumeric

quoted :: Char -> Parser Text
quoted q = T.pack <$> (char q *> manyTill escaped (char q)) <?> "quoted " ++ [q]
  where
    escaped =  char '\\' *> (char q $> q <|> char '\\' $> '\\')
           <|> A.satisfy isAsciiPrint

-- | Parse an atomic word. Single-quoted atoms are parsed without the single
-- quotes and with the characters @'@ and @\\@ unescaped.
atom :: Parser Atom
atom = Atom <$> lexem (quoted '\'' <|> lowerWord) <?> "atom"
{-# INLINE atom #-}

-- | Parse a variable.
var :: Parser Var
var = Var <$> lexem upperWord <?> "var"
{-# INLINE var #-}

-- | Parse a distinct object. Double quotes are not preserved and the characters
-- @'@ and @\\@ are unescaped.
distinctObject :: Parser DistinctObject
distinctObject = DistinctObject <$> lexem (quoted '"') <?> "distinct object"
{-# INLINE distinctObject #-}

-- | Parser a function name.
function :: Parser (Name Function)
function = name <?> "function"
{-# INLINE function #-}

-- | Parse a predicate name.
predicate :: Parser (Name Predicate)
predicate = name <?> "predicate"
{-# INLINE predicate #-}


-- ** Sorts and typess

-- | Parse a sort.
sort :: Parser (Name Sort)
sort = name <?> "sort"
{-# INLINE sort #-}

-- | Parse a sort in sorted polymorphic logic.
tff1Sort :: Parser TFF1Sort
tff1Sort =  SortVariable <$> var
        <|> TFF1Sort <$> sort <*> option [] (parens (tff1Sort `sepBy1` op ','))
        <?> "tff1 sort"

mapping :: Parser a -> Parser ([a], a)
mapping s = (,) <$> option [] (args <* op '>') <*> s
  where
    args = fmap (:[]) s <|> parens (s `sepBy1` op '*')

-- | Parse a type.
type_ :: Parser Type
type_ = uncurry . tff1Type <$> option [] prefix <*> matrix <?> "type"
  where
    prefix = token "!>" *> brackets (sortVar `sepBy1` op ',') <* op ':'
    sortVar = var <* op ':' <* token "$tType"
    matrix = optionalParens (mapping tff1Sort)

-- ** First-order logic

-- | Parse a number.
number :: Parser Number
number =  RationalConstant <$> signed integer <* char '/' <*> integer
      <|> real <$> lexem scientific
      <?> "number"
  where
    real n
      | Sci.base10Exponent n == 0 = IntegerConstant (Sci.coefficient n)
      | otherwise = RealConstant n

-- | Parse a term.
term :: Parser Term
term =  parens term
    <|> Function <$> function <*> option [] (parens (term `sepBy1` op ','))
    <|> Variable <$> var
    <|> Number   <$> number
    <|> DistinctTerm <$> distinctObject
    <?> "term"

-- | Parse the equality and unequality sign.
sign :: Parser Sign
sign = enum <?> "sign"
{-# INLINE sign #-}

-- | Parse a literal.
literal :: Parser Literal
literal =  parens literal
       <|> Equality  <$> term <*> sign <*> term
       <|> Predicate <$> predicate <*> option [] (parens (term `sepBy1` op ','))
       <|> token "$true"  $> Tautology
       <|> token "$false" $> Falsum
       <?> "literal"

-- | Parse a signed literal.
signedLiteral :: Parser (Sign, Literal)
signedLiteral =  (,) <$> option Positive (op '~' $> Negative) <*> literal
             <?> "signed literal"

-- | Parse a clause.
clause :: Parser Clause
clause =  parens clause
      <|> Clause . NEL.fromList <$> signedLiteral `sepBy1` op '|'
      <?> "clause"

-- | Parse a quantifier.
quantifier :: Parser Quantifier
quantifier = enum <?> "quantifier"
{-# INLINE quantifier #-}

-- | Parse a logical connective.
connective :: Parser Connective
connective = enum <?> "connective"
{-# INLINE connective #-}

-- | Given a parser for sort annotations, parse a formula in first-order logic.
firstOrder :: Parser s -> Parser (FirstOrder s)
firstOrder p = do
  f <- unitary
  option f (Connected f <$> connective <*> firstOrder p)
  where
    unitary =  parens (firstOrder p)
           <|> Atomic <$> literal
           <|> Quantified <$> quantifier <*> vs <* op ':' <*> unitary
           <|> Negated <$> (op '~' *> unitary)
           <?> "unitary first order"

    vs = brackets (NEL.fromList <$> v `sepBy1` op ',')
    v = (,) <$> var <*> p

-- | Parse a formula in unsorted first-order logic.
unsortedFirstOrder :: Parser UnsortedFirstOrder
unsortedFirstOrder = firstOrder unsorted
  where unsorted = pure (Unsorted ()) <?> "unsorted"

sorted :: Parser s -> Parser (Sorted s)
sorted s = Sorted <$> optional (op ':' *> s) <?> "sorted"

-- | An alias for 'monomorphicFirstOrder'.
sortedFirstOrder :: Parser SortedFirstOrder
sortedFirstOrder = monomorphicFirstOrder

-- | Parse a formula in sorted monomorphic first-order logic.
monomorphicFirstOrder :: Parser MonomorphicFirstOrder
monomorphicFirstOrder = firstOrder (sorted sort) <?> "tff0"

quantifiedSort :: Parser QuantifiedSort
quantifiedSort = token "$tType" $> QuantifiedSort ()

-- | Parse a formula in sorted polymorphic first-order logic.
polymorphicFirstOrder :: Parser PolymorphicFirstOrder
polymorphicFirstOrder =  firstOrder (sorted (eitherP quantifiedSort tff1Sort))
                     <?> "tff1"


-- ** Units

-- | Parse a formula in a given TPTP language.
formula :: Language -> Parser Formula
formula = \case
  CNF_ -> CNF <$> clause <?> "cnf"
  FOF_ -> FOF <$> unsortedFirstOrder <?> "fof"
  TFF_ -> do
    f <- polymorphicFirstOrder
    return $ case monomorphizeFirstOrder f of
      Just f' -> TFF0 f'
      Nothing -> TFF1 f

-- | Parse a formula role.
role :: Parser (Name Role)
role = keyword <?> "role"
{-# INLINE role #-}

-- | Parse the name of a TPTP language.
lang :: Parser Language
lang = enum <?> "language"
{-# INLINE lang #-}

-- | Parse a TPTP declaration in a given language.
declaration :: Language -> Parser Declaration
declaration l =  token "type" *> op ',' *> optionalParens typeDeclaration
             <|> (role <* op ',' >>= \r -> Formula r <$> formula l)
             <?> "declaration"

-- | Parse a declaration with the @type@ role - either a typing relation or
-- a sort declaration.
typeDeclaration :: Parser Declaration
typeDeclaration =  Sort   <$> atom <* op ':' <*> arity
               <|> Typing <$> atom <* op ':' <*> type_
               <?> "type declaration"
  where
    arity = L.genericLength . fst <$> mapping (token "$tType")

-- | Parse an @include@ statement.
include :: Parser Unit
include = token "include" *> parens (Include <$> atom) <* op '.' <?> "include"

-- | Parse an annotated unit.
annotatedUnit :: Parser Unit
annotatedUnit = do
  l <- lang
  let n = eitherP atom (signed integer)
  let d = declaration l
  let a = maybeP annotation
  parens (Unit <$> n <* op ',' <*> d <*> a) <* op '.'
  <?> "annotated unit"

-- | Parse a TPTP unit.
unit :: Parser Unit
unit = include <|> annotatedUnit <?> "unit"

-- | Parse a TPTP derivation.
derivation :: Parser Derivation
derivation = Derivation <$> manyTill unit endOfInput <?> "derivation"


-- ** Annotations

intro :: Parser Intro
intro = enum <?> "intro"
{-# INLINE intro #-}

info :: Parser Info
info = Info <$> generalList <?> "info"

generalData :: Parser GeneralData
generalData =  token "bind" *> parens (GeneralBind <$> var <* op ',' <*> form)
           <|> GeneralFunction <$> atom <*> generalTerms
           <|> GeneralVariable <$> var
           <|> GeneralNumber   <$> number
           <|> GeneralFormula  <$> form
           <|> GeneralDistinct <$> distinctObject
           <?> "general data"
  where
    generalTerms = option [] (parens (generalTerm `sepBy1` op ','))
    form = char '$' *> do { l <- lang; parens (formula l) }

generalTerm :: Parser GeneralTerm
generalTerm =  GeneralData <$> generalData <*> optional (op ':' *> generalTerm)
           <|> GeneralList <$> generalList
           <?> "general term"

generalList :: Parser [GeneralTerm]
generalList = brackets (generalTerm `sepBy` op ',') <?> "general list"

parent :: Parser Parent
parent = Parent <$> source <*> option [] (op ':' *> generalList) <?> "parent"

source :: Parser Source
source =  app "file"       (File       <$> atom  <*> maybeP atom)
      <|> app "theory"     (Theory     <$> atom  <*> maybeP info)
      <|> app "creator"    (Creator    <$> atom  <*> maybeP info)
      <|> app "introduced" (Introduced <$> intro <*> maybeP info)
      <|> app "inference"  (Inference  <$> atom <* op ','
                                       <*> info <* op ',' <*> ps)
      <|> token "unknown"  $> UnknownSource
      <|> Sources <$> brackets (NEL.fromList <$> source `sepBy` op ',')
      <|> Dag <$> atom
      <?> "source"
  where
    app f as = token f *> parens as
    ps = brackets (parent `sepBy` op ',')

-- | Parse an annotation.
annotation :: Parser Annotation
annotation = (,) <$> source <*> maybeP info <?> "annotation"
