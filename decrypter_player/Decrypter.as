package
{
	/**
	 * DECRYPTER WORKER
	 */

	import com.hurlant.crypto.Crypto;
	import com.hurlant.crypto.symmetric.ICipher;
	import com.hurlant.util.Hex;
	import flash.display.Sprite;
	import flash.events.*;
	import flash.system.MessageChannel;
	import flash.system.Worker;
	import flash.utils.ByteArray;

	public class Decrypter extends Sprite
	{
		// WORKERS
		// workers message channels
		// debugging
		private var playerToDecrypterDebuggingMsgChl:MessageChannel;
		private var decrypterToPlayerDebuggingMsgChl:MessageChannel;
		// startup
		private var playerToDecrypterInitMsgChl:MessageChannel; // ricevo algoritmo, block size e chiave
		private var decrypterToPlayerReadyMsgChl:MessageChannel;
		// progressing
		private var playerToDecrypterProgressingMsgChl:MessageChannel;
		private var decrypterToPlayerProgressingMsgChl:MessageChannel;
		// complete (stream download complete from player to decrypter)
		private var playerToDecrypterCompleteMsgChl:MessageChannel;

		private var bruteForceStopSignal:ByteArray;

		private var cipher:ICipher; // AS3 Crypto library

		private var buffer:ByteArray; // buffer

		private var debug:Boolean; // FIXME debug purpose (default is false)

		// CONSTRUCTOR
		public function Decrypter()
		{
			// debug = true;

			initMessageChannels();

			decrypterToPlayerReadyMsgChl.send(true); // è pronto a ricevere messaggi
		}

		private function initMessageChannels():void
		{
			// debugging
			decrypterToPlayerDebuggingMsgChl = Worker.current.getSharedProperty("decrypterToPlayerDebuggingMsgChl") as MessageChannel;

			playerToDecrypterDebuggingMsgChl = Worker.current.getSharedProperty("playerToDecrypterDebuggingMsgChl") as MessageChannel;
			playerToDecrypterDebuggingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onDebuggingMessageFromPlayer);

			// startup
			decrypterToPlayerReadyMsgChl = Worker.current.getSharedProperty("decrypterToPlayerReadyMsgChl") as MessageChannel;

			playerToDecrypterInitMsgChl = Worker.current.getSharedProperty("playerToDecrypterInitMsgChl") as MessageChannel;
			playerToDecrypterInitMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onInitMessageFromPlayer);

			// progressing
			decrypterToPlayerProgressingMsgChl = Worker.current.getSharedProperty("decrypterToPlayerProgressingMsgChl") as MessageChannel;

			playerToDecrypterProgressingMsgChl = Worker.current.getSharedProperty("playerToDecrypterProgressingMsgChl") as MessageChannel;
			playerToDecrypterProgressingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromPlayer);

			// complete
			playerToDecrypterCompleteMsgChl = Worker.current.getSharedProperty("playerToDecrypterCompleteMsgChl") as MessageChannel;
			playerToDecrypterCompleteMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onCompleteMessageFromPlayer);

			// non è un msg chl...
			bruteForceStopSignal = Worker.current.getSharedProperty("bruteForceStopSignal") as ByteArray;
		}

		private function onDebuggingMessageFromPlayer(event:Event):void
		{
			var message:String = playerToDecrypterDebuggingMsgChl.receive();
			decrypterToPlayerDebuggingMsgChl.send(message);
		}

		private function onInitMessageFromPlayer(event:Event):void
		{
			var secretInfo:Object = playerToDecrypterInitMsgChl.receive();

			var encryptAlgString:String = secretInfo.algorithm;
			var bufferFixedLength:uint = secretInfo.bufferSize;
			var cryptoKeyString:String = secretInfo.key;

			initBuffer(bufferFixedLength);

			if (debug)
			{
				decrypterToPlayerDebuggingMsgChl.send("Decryption Algorithm is " + encryptAlgString);
				decrypterToPlayerDebuggingMsgChl.send("Block Size is (byte) " + bufferFixedLength);
				decrypterToPlayerDebuggingMsgChl.send("Secret key (string) is " + cryptoKeyString);
			}
			/*
		 *  var cipher:ICipher = Crypto.getCipher("simple-aes128-ctr", key);
		 *	where <key> is a ByteArray representing your key.
		 *	If your key is in a different format, you can use Hex or Base64 to convert it:
		 *	var key:ByteArray = Hex.toArray("01020304050708090a0b0c0d0e0f00");
		 *	var key:ByteArray = Base64.toArray("AQIDBAUGBwgJCgsMDQ4PAA==");
		 */

			initCipher(encryptAlgString, Hex.toArray(Hex.fromString(cryptoKeyString)));
		}

		private function initBuffer(bufferLength:uint):void
		{
			buffer = new ByteArray();
			buffer.shareable = true; // passaggio per riferimento!!!
			buffer.length = bufferLength;
		}

		private function initCipher(algorithm:String, key:ByteArray):void
		{
			// AS3 Crypto library
			try
			{
				cipher = Crypto.getCipher(algorithm, key);
			}
			catch (error:Error)
			{
				var errorString:String;
				errorString = error.name + error.errorID + error.message;
				decrypterToPlayerDebuggingMsgChl.send(errorString);
			}
		}

		private function onProgressingMessageFromPlayer(event:Event):void
		{
			if (bruteForceStopSignal[0] == false)
			{
				var bytesFromPlayer:ByteArray = playerToDecrypterProgressingMsgChl.receive();

				fillBufferThenDecryptIt(bytesFromPlayer);

				bytesFromPlayer.clear(); // per non sprecare memoria
			}
			else
			{
				playerToDecrypterProgressingMsgChl.removeEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromPlayer);
			}
		}

		private function fillBufferThenDecryptIt(source:ByteArray):void
		{
			while (buffer.position < buffer.length && source.position < source.length)
			{
				buffer.writeByte(source.readByte()); // write e read incrementano position automaticamente
			}

			if (buffer.position == buffer.length)
			{
				var length:uint = buffer.length; // decifrare il buffer lo riporta alla lunghezza che aveva prima della cifratura!
				decryptAndSendToPlayer(buffer);
				initBuffer(length); // resetto il buffer
			}

			if (source.position < source.length)
			{
				fillBufferThenDecryptIt(source); // riparte da position
			}
		}

		private function decryptAndSendToPlayer(byteArray:ByteArray):void
		{
			decryptWithCrypto(byteArray); // lo decripto

			// adesso è decifrato... (il decrypting è in place!)
			decrypterToPlayerProgressingMsgChl.send(byteArray); // coda limitata o no è uguale
		}

		private function decryptWithCrypto(byteArray:ByteArray):void
		{
			try
			{
				cipher.decrypt(byteArray);
			}
			catch (error:Error)
			{
				// var errorString:String;
				// errorString = error.name + error.errorID + error.message;
				// decrypterToPlayerDebuggingMsgChl.send(errorString);
			}
		}

		private function onCompleteMessageFromPlayer(event:Event):void
		{
			var streamCompleted:Boolean = playerToDecrypterCompleteMsgChl.receive(); // var inutile, mi serve solo sapere che è finito

			// all'ultimo giro il buffer rimane incompleto, ma voglio decriptare solo la parte riempita, non tutto!
			var lastBuffer:ByteArray = new ByteArray();
			lastBuffer.shareable = true;
			lastBuffer.writeBytes(buffer, 0, buffer.position);

			decryptAndSendToPlayer(lastBuffer);
		}

	} // class closed
} // package closed