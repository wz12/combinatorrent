module Process.Peer.Receiver
    ( start )
where

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception (assert)

import Control.Monad.Reader
import Control.Monad.State

import Prelude hiding (catch, log)

import qualified Data.Attoparsec as A
import qualified Data.ByteString as B
import qualified Data.Serialize.Get as G


import Data.Word

import System.IO

import Process
import Supervisor
import Protocol.Wire


data CF = CF { rpMsgCh :: TChan (Message, Integer) }

instance Logging CF where
    logName _ = "Process.Peer.Receiver"

start :: Handle -> TChan (Message, Integer)
          -> SupervisorChannel -> IO ThreadId
start h ch supC = do
   hSetBuffering h NoBuffering
   spawnP (CF ch) h
        (catchP readSend
               (defaultStopHandler supC))

readSend :: Process CF Handle ()
readSend = do
    h <- get
    c <- asks rpMsgCh
    bs' <- liftIO $ B.hGet h 4
    l <- conv bs'
    if (l == 0)
        then return ()
        else do bs <- {-# SCC "hGet_From_BS" #-} liftIO $ B.hGet h (fromIntegral l)
                let sz = B.length bs
                case A.parse (getAPMsg sz) bs of
                    A.Done r msg ->
                        assert (B.null r) $ liftIO . atomically $
                            writeTChan c (msg, fromIntegral l)
                    _ -> do warningP "Incorrect parse in receiver, dying!"
                            stopP
    readSend

conv :: B.ByteString -> Process CF Handle Word32
conv bs = do
    case G.runGet G.getWord32be bs of
      Left err -> do warningP $ "Incorrent parse in receiver, dying: " ++ show err
                     stopP
      Right i -> return i
