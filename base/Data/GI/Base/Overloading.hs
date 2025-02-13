{-# LANGUAGE TypeOperators, KindSignatures, DataKinds, PolyKinds,
             TypeFamilies, UndecidableInstances, EmptyDataDecls,
             MultiParamTypeClasses, FlexibleInstances, ConstraintKinds,
             AllowAmbiguousTypes, FlexibleContexts, ScopedTypeVariables,
             TypeApplications, OverloadedStrings #-}

-- | Helpers for dealing with overladed properties, signals and
-- methods.

module Data.GI.Base.Overloading
    ( -- * Type level inheritance
      ParentTypes
    , HasParentTypes
    , IsDescendantOf

    , asA

    -- * Looking up attributes in parent types
    , AttributeList
    , HasAttributeList
    , ResolveAttribute
    , HasAttribute
    , HasAttr

    -- * Looking up signals in parent types
    , SignalList
    , ResolveSignal
    , HasSignal

    -- * Looking up methods in parent types
    , MethodResolutionFailed
    , UnsupportedMethodError
    , OverloadedMethodInfo(..)
    , OverloadedMethod(..)
    , MethodProxy(..)

    , ResolvedSymbolInfo(..)
    , resolveMethod
    ) where

import Data.Coerce (coerce)
import Data.Kind (Type)

import GHC.Exts (Constraint)
import GHC.TypeLits

import Data.GI.Base.BasicTypes (ManagedPtrNewtype, ManagedPtr(..))

import Data.Text (Text)
import qualified Data.Text as T

-- | Look in the given list of (symbol, tag) tuples for the tag
-- corresponding to the given symbol. If not found raise the given
-- type error.
type family FindElement (m :: Symbol) (ms :: [(Symbol, Type)])
    (typeError :: ErrorMessage) :: Type where
    FindElement m '[] typeError = TypeError typeError
    FindElement m ('(m, o) ': ms) typeError = o
    FindElement m ('(m', o) ': ms) typeError = FindElement m ms typeError

-- | Check whether a type appears in a list. We specialize the
-- names/types a bit so the error messages are more informative.
type family CheckForAncestorType t (a :: Type) (as :: [Type]) :: Constraint where
  CheckForAncestorType t a '[] = TypeError ('Text "Required ancestor ‘"
                                            ':<>: 'ShowType a
                                            ':<>: 'Text "’ not found for type ‘"
                                            ':<>: 'ShowType t ':<>: 'Text "’.")
  CheckForAncestorType t a (a ': as) = ()
  CheckForAncestorType t a (b ': as) = CheckForAncestorType t a as

-- | Check that a type is in the list of `ParentTypes` of another
-- type.
type family IsDescendantOf (parent :: Type) (descendant :: Type) :: Constraint where
    -- Every object is defined to be a descendant of itself.
    IsDescendantOf d d = ()
    IsDescendantOf p d = CheckForAncestorType d p (ParentTypes d)

-- | All the types that are ascendants of this type, including
-- interfaces that the type implements.
type family ParentTypes a :: [Type]

-- | A constraint on a type, to be fulfilled whenever it has a type
-- instance for `ParentTypes`. This leads to nicer errors, thanks to
-- the overlappable instance below.
class HasParentTypes (o :: Type)

-- | Default instance, which will give rise to an error for types
-- without an associated `ParentTypes` instance.
instance {-# OVERLAPPABLE #-}
    TypeError ('Text "Type ‘" ':<>: 'ShowType a ':<>:
               'Text "’ does not have any known parent types.")
    => HasParentTypes a

-- | Safe coercions to a parent class. For instance:
--
-- > #show $ label `asA` Gtk.Widget
--
asA :: (ManagedPtrNewtype a, ManagedPtrNewtype b,
        HasParentTypes b, IsDescendantOf a b)
    => b -> (ManagedPtr a -> a) -> a
asA obj _constructor = coerce obj

-- | The list of attributes defined for a given type. Each element of
-- the list is a tuple, with the first element of the tuple the name
-- of the attribute, and the second the type encoding the information
-- of the attribute. This type will be an instance of
-- `Data.GI.Base.Attributes.AttrInfo`.
type family AttributeList a :: [(Symbol, Type)]

-- | A constraint on a type, to be fulfilled whenever it has a type
-- instance for `AttributeList`. This is here for nicer error
-- reporting.
class HasAttributeList a

-- | Default instance, which will give rise to an error for types
-- without an associated `AttributeList`.
instance {-# OVERLAPPABLE #-}
    TypeError ('Text "Type ‘" ':<>: 'ShowType a ':<>:
               'Text "’ does not have any known attributes.")
    => HasAttributeList a

-- | Return the type encoding the attribute information for a given
-- type and attribute.
type family ResolveAttribute (s :: Symbol) (o :: Type) :: Type where
    ResolveAttribute s o = FindElement s (AttributeList o)
                           ('Text "Unknown attribute ‘" ':<>:
                            'Text s ':<>: 'Text "’ for object ‘" ':<>:
                            'ShowType o ':<>: 'Text "’.")

-- | Whether a given type is in the given list. If found, return
-- @success@, otherwise return @failure@.
type family IsElem (e :: Symbol) (es :: [(Symbol, Type)]) (success :: k)
    (failure :: ErrorMessage) :: k where
    IsElem e '[] success failure = TypeError failure
    IsElem e ( '(e, t) ': es) success failure = success
    IsElem e ( '(other, t) ': es) s f = IsElem e es s f

-- | A constraint imposing that the given object has the given attribute.
type family HasAttribute (attr :: Symbol) (o :: Type) :: Constraint where
    HasAttribute attr o = IsElem attr (AttributeList o)
                          (() :: Constraint) -- success
                          ('Text "Attribute ‘" ':<>: 'Text attr ':<>:
                           'Text "’ not found for type ‘" ':<>:
                           'ShowType o ':<>: 'Text "’.")

-- | A constraint that enforces that the given type has a given attribute.
class HasAttr (attr :: Symbol) (o :: Type)
instance HasAttribute attr o => HasAttr attr o

-- | The list of signals defined for a given type. Each element of the
-- list is a tuple, with the first element of the tuple the name of
-- the signal, and the second the type encoding the information of the
-- signal. This type will be an instance of
-- `Data.GI.Base.Signals.SignalInfo`.
type family SignalList a :: [(Symbol, Type)]

-- | Return the type encoding the signal information for a given
-- type and signal.
type family ResolveSignal (s :: Symbol) (o :: Type) :: Type where
    ResolveSignal s o = FindElement s (SignalList o)
                        ('Text "Unknown signal ‘" ':<>:
                         'Text s ':<>: 'Text "’ for object ‘" ':<>:
                         'ShowType o ':<>: 'Text "’.")

-- | A constraint enforcing that the signal exists for the given
-- object, or one of its ancestors.
type family HasSignal (s :: Symbol) (o :: Type) :: Constraint where
    HasSignal s o = IsElem s (SignalList o)
                    (() :: Constraint) -- success
                    ('Text "Signal ‘" ':<>: 'Text s ':<>:
                     'Text "’ not found for type ‘" ':<>:
                     'ShowType o ':<>: 'Text "’.")

-- | A constraint that always fails with a type error, for
-- documentation purposes.
type family UnsupportedMethodError (s :: Symbol) (o :: Type) :: Type where
  UnsupportedMethodError s o =
    TypeError ('Text "Unsupported method ‘" ':<>:
               'Text s ':<>: 'Text "’ for object ‘" ':<>:
               'ShowType o ':<>: 'Text "’.")

-- | Returned when the method is not found, hopefully making
-- the resulting error messages somewhat clearer.
type family MethodResolutionFailed (method :: Symbol) (o :: Type) where
    MethodResolutionFailed m o =
        TypeError ('Text "Unknown method ‘" ':<>:
                   'Text m ':<>: 'Text "’ for type ‘" ':<>:
                   'ShowType o ':<>: 'Text "’.")

-- | Class for types containing the information about an overloaded
-- method of type @o -> s@.
class OverloadedMethod i o s where
  overloadedMethod :: o -> s -- ^ The actual method being invoked.

-- | Information about a fully resolved symbol, for debugging
-- purposes.
data ResolvedSymbolInfo = ResolvedSymbolInfo {
  resolvedSymbolName      :: Text
  , resolvedSymbolURL     :: Text
  }

instance Show ResolvedSymbolInfo where
  -- Format as a hyperlink on modern terminals (older
  -- terminals should ignore the hyperlink part).
  show info = T.unpack ("\ESC]8;;" <> resolvedSymbolURL info
                         <> "\ESC\\" <> resolvedSymbolName info
                         <> "\ESC]8;;\ESC\\")

-- | This is for debugging purposes, see `resolveMethod` below.
class OverloadedMethodInfo i o where
  overloadedMethodInfo :: Maybe ResolvedSymbolInfo

-- | A proxy for carrying the types `MethodInfoName` needs (this is used
-- for `resolveMethod`, see below).
data MethodProxy (info :: Type) (obj :: Type) = MethodProxy

-- | Return the fully qualified method name that a given overloaded
-- method call resolves to (mostly useful for debugging).
--
-- > resolveMethod widget #show
resolveMethod :: forall info obj. (OverloadedMethodInfo info obj) =>
                 obj -> MethodProxy info obj -> Maybe ResolvedSymbolInfo
resolveMethod _o _p = overloadedMethodInfo @info @obj
