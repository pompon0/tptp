{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module       : Main
-- Description  : QuickCheck specification for the tptp library.
-- Copyright    : (c) Evgenii Kotelnikov, 2019
-- License      : GPL-3
-- Maintainer   : evgeny.kotelnikov@gmail.com
-- Stability    : experimental
--
-- Defines properties of the tptp library and runs QuickCheck on them.
--

module Main where

import Test.QuickCheck hiding (Function, function, Positive)

import Data.Attoparsec.Text (Parser, parseOnly, endOfInput)
import Data.Text.Prettyprint.Doc (layoutPretty, defaultLayoutOptions)
import Data.Text.Prettyprint.Doc.Render.Text (renderStrict)

import Data.TPTP
import Data.TPTP.Parse.Combinators
import Data.TPTP.Pretty

import Generators ()
import Normalizers

-- * Helper functions

-- | Idempotent parsing / pretty printing modulo normalization
ippModulo :: (Show a, Eq a, Pretty a) => (a -> a) -> Parser a -> a -> Property
ippModulo normalize p a =
  whenFail (print t) $ case parseOnly (p <* endOfInput) t of
    Left err -> whenFail (putStrLn $ "Parsing error: " ++ err) False
    Right a' -> normalize a' === normalize a
  where
    t = renderStrict $ layoutPretty defaultLayoutOptions (pretty a)

-- | Idempotent parsing / pretty printing
ipp :: (Show a, Eq a, Pretty a) => Parser a -> a -> Property
ipp = ippModulo id


-- * Properties

-- ** Generators

prop_validAtom :: Atom -> Bool
prop_validAtom (Atom t) = isValidAtom t

prop_validVar :: Var -> Bool
prop_validVar (Var t) = isValidVar t

prop_validDistinctObject :: DistinctObject -> Bool
prop_validDistinctObject (DistinctObject t) = isValidDistinctObject t


-- ** Names

prop_ipp_Atom :: Atom -> Property
prop_ipp_Atom = ipp atom

prop_ipp_Var :: Var -> Property
prop_ipp_Var = ipp var

prop_ipp_DistinctObject :: DistinctObject -> Property
prop_ipp_DistinctObject = ipp distinctObject

prop_ipp_Function :: Name Function -> Property
prop_ipp_Function = ipp function

prop_ipp_Predicate :: Name Predicate -> Property
prop_ipp_Predicate = ipp predicate


-- ** Sorts and types

prop_ipp_Sort :: Name Sort -> Property
prop_ipp_Sort = ipp sort

prop_ipp_TFF1Sort :: TFF1Sort -> Property
prop_ipp_TFF1Sort = ipp tff1Sort

prop_ipp_Type :: Type -> Property
prop_ipp_Type = ippModulo normalizeType type_


-- ** First-order logic

prop_ipp_Number :: Number -> Property
prop_ipp_Number = ipp number

prop_ipp_Term :: Term -> Property
prop_ipp_Term = ipp term

prop_ipp_Literal :: Literal -> Property
prop_ipp_Literal = ipp literal

prop_ipp_Clause :: Clause -> Property
prop_ipp_Clause = ipp clause

prop_ipp_UnsortedFO :: UnsortedFirstOrder -> Property
prop_ipp_UnsortedFO = ippModulo reassociate unsortedFirstOrder

prop_ipp_MonomorphicFO :: MonomorphicFirstOrder -> Property
prop_ipp_MonomorphicFO = ippModulo reassociate monomorphicFirstOrder

prop_ipp_PolymorphicFO :: PolymorphicFirstOrder -> Property
prop_ipp_PolymorphicFO = ippModulo reassociate polymorphicFirstOrder


-- ** Units

prop_ipp_Unit :: Unit -> Property
prop_ipp_Unit = ippModulo normalizeUnit unit

prop_ipp_Derivation :: Derivation -> Property
prop_ipp_Derivation = ippModulo normalizeDerivation derivation


-- ** Annotations

prop_ipp_Parent :: Parent -> Property
prop_ipp_Parent = ippModulo normalizeParent parent

prop_ipp_GeneralData :: GeneralData -> Property
prop_ipp_GeneralData = ippModulo normalizeGeneralData generalData

prop_ipp_GeneralTerm :: GeneralTerm -> Property
prop_ipp_GeneralTerm = ippModulo normalizeGeneralTerm generalTerm

prop_ipp_Info :: Info -> Property
prop_ipp_Info = ippModulo normalizeInfo info

prop_ipp_Source :: Source -> Property
prop_ipp_Source = ippModulo normalizeSource source


-- * Runner

return []

main :: IO Bool
main = $forAllProperties $ quickCheckWithResult stdArgs{maxSuccess=1000}
