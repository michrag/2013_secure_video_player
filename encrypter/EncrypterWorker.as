package {
    /**
     * ENCRYPTER BACKGROUND (actual encrypter) WORKER
     */

    import com.hurlant.crypto.Crypto;
    import com.hurlant.crypto.symmetric.ICipher;
    import com.hurlant.util.Hex;
    import flash.display.Sprite;
    import flash.events.*;
    import flash.system.MessageChannel;
    import flash.system.Worker;
    import flash.utils.ByteArray;

    public class EncrypterWorker extends Sprite {
        // WORKERS
        // workers message channels
        // debugging
        private var mainToEncrypterDebuggingMsgChl:MessageChannel;
        private var encrypterToMainDebuggingMsgChl:MessageChannel;
        // startup
        private var mainToEncrypterInitMsgChl:MessageChannel; // ricevo: algoritmo, block size e chiave
        private var encrypterToMainReadyMsgChl:MessageChannel;
        // progressing
        private var mainToEncrypterProgressingMsgChl:MessageChannel;
        private var encrypterToMainProgressingMsgChl:MessageChannel;
        // complete
        private var mainToEncrypterCompleteMsgChl:MessageChannel;
        private var encrypterToMainCompleteMsgChl:MessageChannel;

        // AS3 Crypto library
        private var cipher:ICipher;
        // private var encryptAlgString:String;
        // private var cryptoKey:ByteArray;

        // buffer
        private var buffer:ByteArray;

        // private var bufferFixedLength:uint;

        // CONSTRUCTOR
        public function EncrypterWorker() {
            initMessageChannels();

            encrypterToMainReadyMsgChl.send(true);
        }

        private function initMessageChannels():void {
            // debugging
            encrypterToMainDebuggingMsgChl = Worker.current.getSharedProperty("encrypterToMainDebuggingMsgChl") as MessageChannel;

            mainToEncrypterDebuggingMsgChl = Worker.current.getSharedProperty("mainToEncrypterDebuggingMsgChl") as MessageChannel;
            mainToEncrypterDebuggingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onDebuggingMessageFromMain);

            // startup
            mainToEncrypterInitMsgChl = Worker.current.getSharedProperty("mainToEncrypterInitMsgChl") as MessageChannel;
            mainToEncrypterInitMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onInitMessageFromMain);

            encrypterToMainReadyMsgChl = Worker.current.getSharedProperty("encrypterToMainReadyMsgChl") as MessageChannel;

            // progressing
            encrypterToMainProgressingMsgChl = Worker.current.getSharedProperty("encrypterToMainProgressingMsgChl") as MessageChannel;

            mainToEncrypterProgressingMsgChl = Worker.current.getSharedProperty("mainToEncrypterProgressingMsgChl") as MessageChannel;
            mainToEncrypterProgressingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromMain);

            // complete
            encrypterToMainCompleteMsgChl = Worker.current.getSharedProperty("encrypterToMainCompleteMsgChl") as MessageChannel;

            mainToEncrypterCompleteMsgChl = Worker.current.getSharedProperty("mainToEncrypterCompleteMsgChl") as MessageChannel;
            mainToEncrypterCompleteMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onCompleteMessageFromMain);
        }

        private function onDebuggingMessageFromMain(event:Event):void {
            var message:String = mainToEncrypterDebuggingMsgChl.receive();
            encrypterToMainDebuggingMsgChl.send(message);
        }

        private function onInitMessageFromMain(event:Event):void {
            var secretInfo:Object = mainToEncrypterInitMsgChl.receive();

            var encryptAlgString:String = secretInfo.algorithm;
            var bufferFixedLength:uint = secretInfo.bufferSize;
            var cryptoKeyString:String = secretInfo.key;

            initBuffer(bufferFixedLength);

            encrypterToMainDebuggingMsgChl.send("\nencryption Algorithm is " + encryptAlgString);
            encrypterToMainDebuggingMsgChl.send("buffer Size is (byte) " + bufferFixedLength);
            encrypterToMainDebuggingMsgChl.send("secret key is " + cryptoKeyString + "\n"); // FIXME così la chiave sarà scritta in chiaro nel file di log!!!

            initCipher(encryptAlgString, Hex.toArray(Hex.fromString(cryptoKeyString)));
        }

        private function initBuffer(bufferLength:uint):void {
            buffer = new ByteArray();
            buffer.shareable = true; // passaggio per riferimento!!!
            buffer.length = bufferLength;
        }

        private function initCipher(algorithm:String, key:ByteArray):void {
            // AS3 Crypto library
            try {
                cipher = Crypto.getCipher(algorithm, key);
            } catch (error:Error) {
                var errorString:String;
                errorString = error.name + error.errorID + error.message;
                encrypterToMainDebuggingMsgChl.send(errorString);
            }
        }

        private function onProgressingMessageFromMain(event:Event):void {
            var bytesFromMain:ByteArray = mainToEncrypterProgressingMsgChl.receive();

            fillBufferThenEncryptIt(bytesFromMain);

            bytesFromMain.clear(); // // fondamentale per non sprecare memoria

            // decrypterToPlayerDebuggingMsgChl.send("bytesFromPlayer.length = " + bytesFromPlayer.length);
            // lo cleara davvero?! - sembra di sì! (length = 0)
        }

        private function fillBufferThenEncryptIt(source:ByteArray):void {
            while (buffer.position < buffer.length && source.position < source.length) {
                buffer.writeByte(source.readByte()); // write e read incrementano position automaticamente
            }

            if (buffer.position == buffer.length) {
                // encryptAndSendToMain(buffer);
                // initBuffer(); // resetto il buffer
                var length:uint = buffer.length; // cifrare il buffer ne modifica la lunghezza!
                encryptAndSendToMain(buffer);
                initBuffer(length); // resetto il buffer
            }

            if (source.position < source.length) {
                fillBufferThenEncryptIt(source); // riparte da position
            }
        }

        private function encryptAndSendToMain(byteArray:ByteArray):void {
            encryptWithCrypto(byteArray);

            // encrypting in place!
            encrypterToMainProgressingMsgChl.send(byteArray);
        }

        private function encryptWithCrypto(byteArray:ByteArray):void {
            try {
                cipher.encrypt(byteArray); // è un ENCRYPTER!!!
            } catch (error:Error) {
                var errorString:String;
                errorString = error.name + error.errorID + error.message;
                encrypterToMainDebuggingMsgChl.send(errorString);
            }
        }

        private function onCompleteMessageFromMain(event:Event):void {
            var streamCompleted:Boolean = mainToEncrypterCompleteMsgChl.receive(); // var inutile, mi serve solo sapere che è finito

            // all'ultimo giro il buffer rimane incompleto, ma voglio encriptare solo la parte riempita, non tutto!
            var lastBuffer:ByteArray = new ByteArray();
            lastBuffer.shareable = true;
            lastBuffer.writeBytes(buffer, 0, buffer.position);

            encryptWithCrypto(lastBuffer);

            encrypterToMainCompleteMsgChl.send(lastBuffer);
        }

    } // class closed
} // package closed
