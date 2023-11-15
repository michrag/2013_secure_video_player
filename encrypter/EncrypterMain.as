package {
    /**
     * ENCRYPTER MAIN WORKER
     */

    import fl.controls.*;
    import fl.controls.TextArea;
    import flash.net.FileFilter;
    import flash.text.TextFormat;
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.*;
    import flash.filesystem.*;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.URLRequest;
    import flash.net.URLStream;
    import flash.system.Capabilities;
    import flash.system.MessageChannel;
    import flash.system.Worker;
    import flash.system.WorkerDomain;
    import flash.system.WorkerState;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.Timer;


    public class EncrypterMain extends Sprite {
        // GLOBAL VARIABLES

        // FONDAMENTALI
        private var urlRequest:URLRequest;
        private var urlStream:URLStream;

        private var inputFileURL:String;
        private var inputFileName:String;

        // file
        private var rootDirectory:File;
        private var inputDirectory:File;
        private var outputDirectory:File;
        private var outputFile:File;
        private var outputFileStream:FileStream;

        private var firstProgress:Boolean; // la dimensione totale del file di input la conosco solo col progress
        private var inputFileSizeInBytes:uint; // dimensione totale file da encriptare
        private var inputFileSizeInMegaBytes:Number;
        private var encryptedBytes:uint; // counters per progress bars
        private var encryptedBytesAtPreviousUpdate:uint; // per calcolare la velocità...
        private var encryptedBytesPerSecond:uint; // perché timerUpdateInterval == 1000, altrimenti no!
        private var encryptedMegaBytes:Number;


        // WORKERS
        [Embed(source = "../bin/EncrypterWorker.swf", mimeType = "application/octet-stream")]
        private static var encrypterWorkerByteClass:Class;
        private var encrypterWorker:Worker;
        // workers message channels
        // debugging
        private var mainToEncrypterDebuggingMsgChl:MessageChannel;
        private var encrypterToMainDebuggingMsgChl:MessageChannel;
        // startup
        private var mainToEncrypterInitMsgChl:MessageChannel; // passa all'encrypter: algoritmo, block size e chiave
        private var encrypterToMainReadyMsgChl:MessageChannel;
        // progressing
        private var mainToEncrypterProgressingMsgChl:MessageChannel;
        private var encrypterToMainProgressingMsgChl:MessageChannel;
        // complete
        private var mainToEncrypterCompleteMsgChl:MessageChannel;
        private var encrypterToMainCompleteMsgChl:MessageChannel;


        // UI
        // textFormat
        private var textFormat:TextFormat;
        // textArea
        private var textArea:TextArea;
        // progress bar
        private const progressBarHeight:uint = 50;
        private var encryptingProgressBar:ProgressBar;
        // pulsanti
        private const buttonHeight:uint = progressBarHeight;
        private const bottomUIpanelHeight:uint = progressBarHeight + buttonHeight * 3;
        private var buttonWidth:uint;
        private var bottomButtonsCounter:int; // per fare i pulsanti con la stessa larghezza
        private var progressPercentFakeButton:Button;
        private var timeElapsedFakeButton:Button;
        private var timeRemainingFakeButton:Button;
        private var encryptedMBfakeButton:Button;
        private var toEncryptMBfakeButton:Button;
        private var encryptionSpeedFakeButton:Button;
        private var deleteInputFileCheckBox:CheckBox;
        private var closeOnCompleteCheckBox:CheckBox;
        private var saveLogFileCheckBox:CheckBox;

        private var timer:Timer;
        private const timerUpdateInterval:uint = 1000; // millisecondi. così la velocità la calcolo semplicemente...! (NON modificarlo!)


        // parametri per eNcrypting passati da riga di comando!
        private var encryptionAlgorithm:String;
        private var encryptionBufferSize:uint;
        private var cryptoKeyString:String;

        private var encryptionBlockSizeAfterEncryption:uint; // informazione fondamentale!!! as3crypto library aggiunge un po' di bytes (l'IV) al blocco che cifra


        // CONSTRUCTOR
        public function EncrypterMain() {
            rootDirectory = File.documentsDirectory.resolvePath("AIR_encrypter");
            rootDirectory.createDirectory(); // se già c'è non fa nulla

            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, invokeHandler);

            firstProgress = true;

            initTextFormat();

            initTextArea();

            sendToTextArea(Capabilities.cpuArchitecture);
            sendToTextArea(Capabilities.manufacturer);
            sendToTextArea(Capabilities.os);
            sendToTextArea(Capabilities.playerType);
            sendToTextArea(Capabilities.version);

            var startDate:Date = new Date();

            sendToTextArea("started on " + startDate.toLocaleString());

            //generateDummySecretKey();

            // Make sure the app is visible and stage available
            addEventListener(Event.ADDED_TO_STAGE, addedToStageHandler);
        }


        private function invokeHandler(invocation:InvokeEvent):void {
            inputDirectory = rootDirectory.resolvePath("input");

            //sendToTextArea("\ninput folder is: " + "\"" + inputDirectory.nativePath + "\"" );

            // viene chiamato tardissimo!!!! devo fare tutte le init qui!!!
            if (invocation.arguments.length >= 2) {
                inputFileName = invocation.arguments[0];
                sendToTextArea("\ninput file name is: " + "\"" + inputFileName + "\"" + "\n");

                switch (uint(invocation.arguments[1])) {
                    case 1:
                        encryptionAlgorithm = "simple-aes128-cbc";
                        break;

                    case 2:
                        encryptionAlgorithm = "simple-aes192-cbc";
                        break;

                    case 3:
                        encryptionAlgorithm = "simple-aes256-cbc";
                        break;

                    default:
                        sendToTextArea("first parameter (algorithm ID) must be 1 (AES 128) or 2 (AES 192) or 3 (AES 256) !");
                }

                // FIXME fare qualche controllo per buffer size e key (length)....?!
                encryptionBufferSize = uint(invocation.arguments[2]);

                cryptoKeyString = invocation.arguments[3];

                //sendToTextArea(encryptionAlgorithm);
                //sendToTextArea(encryptionBufferSize.toString());
                //sendToTextArea(cryptoKeyString);

                initOutputFile(); // lo devo fare PRIMA di inizializzare l'input file, per poter scrivere eventuale log file in caso di errore
                initInputFileURL();

                initEncrypterWorker();
            } else {
                sendToTextArea("ERROR! expected four arguments: inputFileName algorithmID bufferSize secretKey");
                sendToTextArea("example: EncrypterMain.exe inputVideo.flv 1 65536 a1b2c3d4e5f6g7h8");
                sendToTextArea("algorithmID = 1 => AES 128, 2 => AES 192, 3 => AES 256");
                sendToTextArea("bufferSize value is in bytes");
                sendToTextArea("input file MUST BE placed in: " + "\"" + inputDirectory.nativePath + "\"");
                inputDirectory.createDirectory(); // se non c'era la creo
            }
        }


        private function initTextFormat():void {
            textFormat = new TextFormat();
            textFormat.font = "Kalinga"; // "Courier New"
            textFormat.size = 20;
        }


        private function initTextArea():void {
            textArea = new TextArea();

            textArea.editable = false;
            textArea.wordWrap = false;

            // FUNZIONAAAAAAA!!!
            textArea.setStyle("textFormat", textFormat);

            addChild(textArea);
        }


        private function sendToTextArea(string:String):void {
            textArea.text += (string + "\n");
        }


        private function initOutputFile():void {
            // Use the documents directory to write files that a user expects to use outside your application
            //outputDirectory = File.documentsDirectory.resolvePath("AIR_encrypter/output");  // cartella specifica per l'applicazione

            outputDirectory = rootDirectory.resolvePath("output");
            outputDirectory.createDirectory(); // se già esiste non fa nulla

            outputFile = outputDirectory;

            sendToTextArea("output file will be written in: " + "\"" + outputDirectory.nativePath + "\"");

            // check se il file già esiste
            var existingFileCounter:uint = 0;

            outputFile = outputFile.resolvePath(getOutputFileName(0)); // name of file to write (ci provo)

            sendToTextArea("output file name may be: " + "\"" + outputFile.name + "\"");

            while (outputFile.exists) {
                sendToTextArea("\"" + outputFile.name + "\"" + " ALREADY EXISTS in: " + "\"" + outputDirectory.nativePath + "\"");
                existingFileCounter++;
                outputFile = outputDirectory.resolvePath(getOutputFileName(existingFileCounter));
            }

            sendToTextArea("\noutput file path is: " + "\"" + outputFile.nativePath + "\"");

            outputFileStream = new FileStream();

            //open output file stream in APPEND mode
            outputFileStream.open(outputFile, FileMode.APPEND);
        }


        private function getOutputFileName(fileAlreadyExistsCounter:uint):String {
            var extension:String;

            //sto supponendo che nel inputFileName fornito CI SIA l'estensione e che sia lunga esattamente 3 caratteri (4 col punto)
            extension = inputFileName.substr(inputFileName.length - 4, inputFileName.length); // metto da parte l'estensione (.flv)

            var outputFileName:String;

            outputFileName = inputFileName.substr(0, inputFileName.length - 4); // butto via l'estensione

            outputFileName = outputFileName + "_" + encryptionAlgorithm.substring(7);

            outputFileName += "_encryptionBufferSize" + encryptionBufferSize + "Bytes";

            if (fileAlreadyExistsCounter == 0) {
                outputFileName += extension;
            } else {
                outputFileName += "(" + fileAlreadyExistsCounter.toString() + ")" + extension;
            }

            return outputFileName;
        }


        private function initInputFileURL():void {
            //inputDirectory = rootDirectory.resolvePath("input");

            sendToTextArea("\ninput folder is: " + "\"" + inputDirectory.nativePath + "\"");

            if (!inputDirectory.exists) //se NON esiste FAIL perchè allora dentro non ci sono file!
            {
                sendToTextArea("");
                sendToTextArea("ERROR! input folder " + "\"" + inputDirectory.nativePath + "\"" + " did NOT exist!");
                inputDirectory.createDirectory();
                sendToTextArea("input folder created");
                sendToTextArea("please place input files in the input folder " + "\"" + inputDirectory.nativePath + "\"");
                //sendToTextArea("\nlog file will be saved and application will be closed");
                //writeLogFile( true, false );
                //NativeApplication.nativeApplication.exit(); //NON la chiudo perché se non c'era la cartella di input non ci sono altri file!
                return;
            }

            inputFileURL = inputDirectory.url + "/" + inputFileName;

            sendToTextArea("input file url is: " + "\"" + inputFileURL + "\"" + "\n");
        }


        // WORKERS...
        private function initEncrypterWorker():void {
            if (Worker.isSupported) {
                //trace("Worker supported");
                sendToTextArea("workers supported");
            } else // epic fail, suicidati
            {
                //trace("Worker is NOT supported");
                sendToTextArea("FATAL ERROR! workers are NOT supported!");
                sendToTextArea("\nlog file will be saved and application will be closed");
                writeLogFile(true, false);
                NativeApplication.nativeApplication.exit(); // chiudo automaticamente l'appLICAZIONE
                return;
            }

            // create the background worker
            var encrypterWorkerBytes:ByteArray = new encrypterWorkerByteClass();

            if (encrypterWorkerBytes == null) {
                trace("encrypterWorkerBytes is null");
                sendToTextArea("encrypterWorkerBytes is null");
            }

            encrypterWorker = WorkerDomain.current.createWorker(encrypterWorkerBytes);

            if (encrypterWorker == null) {
                trace("encrypterWorker is null");
                sendToTextArea("encrypterWorker is null");
            }

            initWorkersMessageChannels();

            // start decrypter worker
            encrypterWorker.addEventListener(Event.WORKER_STATE, encrypterWorkerStateHandler);
            encrypterWorker.start();
        }


        private function encrypterWorkerStateHandler(event:Event):void {
            if (encrypterWorker.state == WorkerState.RUNNING) {
                //trace("Encrypter worker started (\"running\")");
                sendToTextArea("encrypter worker started (\"running\")");
            }
        }


        private function initWorkersMessageChannels():void {
            // main to encrypter
            // debugging
            mainToEncrypterDebuggingMsgChl = Worker.current.createMessageChannel(encrypterWorker);
            encrypterWorker.setSharedProperty("mainToEncrypterDebuggingMsgChl", mainToEncrypterDebuggingMsgChl);
            // init msgChl main-> eNcrypter con cui gli passo un object (alg, buffer-aka-block size, key)
            mainToEncrypterInitMsgChl = Worker.current.createMessageChannel(encrypterWorker);
            encrypterWorker.setSharedProperty("mainToEncrypterInitMsgChl", mainToEncrypterInitMsgChl);
            // progressing
            mainToEncrypterProgressingMsgChl = Worker.current.createMessageChannel(encrypterWorker);
            encrypterWorker.setSharedProperty("mainToEncrypterProgressingMsgChl", mainToEncrypterProgressingMsgChl);
            // complete
            mainToEncrypterCompleteMsgChl = Worker.current.createMessageChannel(encrypterWorker);
            encrypterWorker.setSharedProperty("mainToEncrypterCompleteMsgChl", mainToEncrypterCompleteMsgChl);

            // encrypter to main
            // debugging
            encrypterToMainDebuggingMsgChl = encrypterWorker.createMessageChannel(Worker.current);
            encrypterToMainDebuggingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onDebuggingMessageFromEncrypter);
            encrypterWorker.setSharedProperty("encrypterToMainDebuggingMsgChl", encrypterToMainDebuggingMsgChl);
            // startup
            encrypterToMainReadyMsgChl = encrypterWorker.createMessageChannel(Worker.current);
            encrypterToMainReadyMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onStartupMessageFromEncrypter);
            encrypterWorker.setSharedProperty("encrypterToMainReadyMsgChl", encrypterToMainReadyMsgChl);
            // progressing
            encrypterToMainProgressingMsgChl = encrypterWorker.createMessageChannel(Worker.current);
            encrypterToMainProgressingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromEncrypter);
            encrypterWorker.setSharedProperty("encrypterToMainProgressingMsgChl", encrypterToMainProgressingMsgChl);
            // complete
            encrypterToMainCompleteMsgChl = encrypterWorker.createMessageChannel(Worker.current);
            encrypterToMainCompleteMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onCompleteMessageFromEncrypter);
            encrypterWorker.setSharedProperty("encrypterToMainCompleteMsgChl", encrypterToMainCompleteMsgChl);
        }


        private function onDebuggingMessageFromEncrypter(ev:Event):void {
            var message:String = encrypterToMainDebuggingMsgChl.receive();
            //trace("Message from encrypter:", message);
            sendToTextArea(message);
        }


        private function onStartupMessageFromEncrypter(ev:Event):void {
            var encrypterWorkerReady:Boolean = encrypterToMainReadyMsgChl.receive() as Boolean;
            if (encrypterWorkerReady) {
                //trace("Encrypter worker ready");
                sendToTextArea("encrypter worker ready");

                // gli passo le info sicure
                // object = {name1 : value1, name2 : value2,... nameN : valueN} Creates a new object and initializes it with the specified name and value property pairs
                mainToEncrypterInitMsgChl.send({algorithm: encryptionAlgorithm, bufferSize: encryptionBufferSize, key: cryptoKeyString});

                initUrlRequestAndStream();
            } else {
                //trace("Encrypter worker failed to startup!");
                sendToTextArea("encrypter worker failed to startup!");
            }
        }


        private function initUrlRequestAndStream():void {
            /*
               The URLRequest class captures all of the information in a single HTTP request.
               URLRequest objects are passed to the load() methods of the URLStream class to initiate URL downloads
             */
            urlRequest = new URLRequest(inputFileURL);

            /*
               The URLStream class provides low-level access to downloading URLs.
               Data is made available to application code immediately as it is downloaded
               The contents of the downloaded file are made available as raw binary data.
             */
            urlStream = new URLStream();

            initUrlStreamListeners();

            try {
                urlStream.load(urlRequest);
            } catch (error:Error) {
                trace(error.name, error.errorID, error.message);
            }
        }


        private function initUrlStreamListeners():void {
            /*
               URLStream deriva da EventDispatcher
               Registers an event listener object with an EventDispatcher object so that the listener receives notification of an event
               URLStream event progress: Dispatched when data is received as the download operation progresses.
               Data that has been received can be read immediately using the methods of the URLStream class.
             */
            urlStream.addEventListener(Event.OPEN, urlStreamOpenHandler);
            urlStream.addEventListener(ProgressEvent.PROGRESS, urlStreamProgressHandler);
            urlStream.addEventListener(Event.COMPLETE, urlStreamCompleteHandler);

            urlStream.addEventListener(HTTPStatusEvent.HTTP_STATUS, urlStreamHttpStatusHandler);
            urlStream.addEventListener(IOErrorEvent.IO_ERROR, urlStreamIOerrorHandler);
            urlStream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, urlStreamSecurityErrorHandler);
        }


        private function urlStreamOpenHandler(event:Event):void {
            //trace("Stream opened");
            sendToTextArea("stream opened");

            //mainToEncrypterDebuggingMsgChl.send("Stream opened");
        }


        private function urlStreamCompleteHandler(event:Event):void {
            //trace("Stream completed:", event);
            sendToTextArea("stream completed: " + event.toString());

            mainToEncrypterCompleteMsgChl.send(true);
        }


        private function urlStreamHttpStatusHandler(event:HTTPStatusEvent):void {
            //trace("http Status:", event);
            sendToTextArea("http Status: " + event.toString());
        }


        private function urlStreamIOerrorHandler(event:IOErrorEvent):void {
            //trace("IO error:", event);
            sendToTextArea("");
            sendToTextArea("IO error: " + event.toString());

            sendToTextArea("\nERROR! input file " + "\"" + inputFileURL + "\"" + " NOT found!");
            sendToTextArea("please place input file " + "\"" + inputFileName + "\"" + " in the input folder " + "\"" + inputDirectory.nativePath + "\"");
            sendToTextArea("\nlog file will be saved and application will be closed");
            writeLogFile(true, false);
            NativeApplication.nativeApplication.exit(); // se non trovo l'input file, chiudo
        }


        private function urlStreamSecurityErrorHandler(event:SecurityErrorEvent):void {
            //trace("Security Error:", event);
            sendToTextArea("security error: " + event.toString());
        }


        private function urlStreamProgressHandler(event:ProgressEvent):void {
            // cose da fare solo la prima volta
            if (firstProgress) {
                inputFileSizeInBytes = event.bytesTotal; // uso questo come dimensione totale!

                inputFileSizeInMegaBytes = (inputFileSizeInBytes / (1024 * 1024));

                sendToTextArea("input file size (MB) = " + inputFileSizeInMegaBytes.toFixed(2) + "\n");

                checkAvailableSpaceOnDisk();

                firstProgress = false;
            }
            // fine cose da fare solo la prima volta

            var loadedBytes:ByteArray;
            loadedBytes = new ByteArray();
            loadedBytes.shareable = true; // passaggio per riferimento! (più veloce, meno memoria!)

            urlStream.readBytes(loadedBytes); // leggo tutti quelli disponibili!

            mainToEncrypterProgressingMsgChl.send(loadedBytes); // lo passo all'encrypter
        }


        private function checkAvailableSpaceOnDisk():void {
            if (outputDirectory.spaceAvailable < inputFileSizeInBytes) {
                // in realtà l'output file sarà un po' più grande a causa del buffer size che aumenta con l'encryption
                // ma a questo punto non c'è modo di saperlo...!
                // beh potrei farlo al primo msg ricevuto dll'encrypter, lì so la differenza, fare due conti e sapere quanto grossò verrà fuori il file di output...!!!
                sendToTextArea("ERROR! there is NOT enough space in " + "\"" + outputDirectory.nativePath + "\"" + " to write output file!");
                sendToTextArea("please make sure there is at least " + inputFileSizeInMegaBytes.toFixed(2) + " MB");
                sendToTextArea("log file will be saved and application will be closed");
                writeLogFile(true, false);
                // NOTA: almeno su Windows, l'output file è stato comunque creato, ma è di 0 byte
                // e non me lo fa rimuovere (outputFile.deleteFile o deleteFileAsync)... pazienza!!!
                NativeApplication.nativeApplication.exit(); // chiudo automaticamente l'appLICAZIONE
            } else {
                sendToTextArea("... good, there is enough space");
                sendToTextArea("encrypting...\n");
            }
        }


        private function onProgressingMessageFromEncrypter(ev:Event):void {
            var encryptedBuffer:ByteArray = encrypterToMainProgressingMsgChl.receive(); //lo ricevo

            encryptionBlockSizeAfterEncryption = encryptedBuffer.length;

            writeBytesToOutputFile(encryptedBuffer);
        }


        private function writeBytesToOutputFile(bytes:ByteArray):void {
            encryptedBytes = encryptedBytes + bytes.length; // aggiorno il contatore

            encryptedMegaBytes = encryptedBytes / (1024 * 1024);

            outputFileStream.writeBytes(bytes);

            //trace("bytes encrypted =", bytesEncrypted, "total =", totalBytes);
            //sendToTextArea( "bytes encrypted = " + bytesEncrypted + " / total = " + totalBytes );

            bytes.clear(); // fondamentale per non sprecare memoria
        }


        private function onCompleteMessageFromEncrypter(ev:Event):void {
            var encryptedBuffer:ByteArray = encrypterToMainCompleteMsgChl.receive(); //lo ricevo

            writeBytesToOutputFile(encryptedBuffer);

            outputFileStream.close();

            //trace("encryption complete!!");
            sendToTextArea("\nencryption complete!");

            printInfoOnComplete();

            timer.stop();

            updateUserInterface(); // perché l'intervallo è di un secondo, sennò alla fine non mostrava il 100%

            encryptionSpeedFakeButton.label = new String("done! :)");

            timeRemainingFakeButton.label = new String("time remaining = " + getTimeString(0));

            var endDate:Date = new Date();

            sendToTextArea("completed on " + endDate.toLocaleString());

            if (deleteInputFileCheckBox.selected)
                deleteInputFile();

            if (saveLogFileCheckBox.selected)
                writeLogFile(false, false);

            if (closeOnCompleteCheckBox.selected)
                NativeApplication.nativeApplication.exit(); // chiudo automaticamente l'appLICAZIONE
        }


        private function printInfoOnComplete():void {
            var timeElapsed:int = getTimer(); // MILLIsecondi!!!
            var timeElapsedString:String = getTimeString(timeElapsed / 1000);

            //trace("time elapsed =", timeElapsedString);
            sendToTextArea("time elapsed = " + timeElapsedString);

            //trace("Block Size before encrypting was (byte)", encryptionBlockSize);
            sendToTextArea("");
            sendToTextArea("*****************************************************************");
            sendToTextArea("buffer size before encryption was (byte) " + encryptionBufferSize);

            //trace("Block Size after encryption is (byte)", encryptionBlockSizeAfterEncryption);
            sendToTextArea("buffer size after encryption is (byte) " + encryptionBlockSizeAfterEncryption + "  <<<--- THIS IS A CRUCIAL INFORMATION !!! decryption buffer size MUST BE equal to this !!! ");

            var difference:int = encryptionBlockSizeAfterEncryption - encryptionBufferSize;

            //trace("difference is (byte)", difference);
            sendToTextArea("difference is (byte) " + difference);
            sendToTextArea("*****************************************************************");
            sendToTextArea("");
        }


        private function getTimeString(totalSeconds:int):String {
            var hours:int = totalSeconds / (60 * 60);
            var minutes:int = totalSeconds / 60;
            var seconds:int = totalSeconds % 60;

            var hoursString:String = new String();
            var minutesString:String;
            var secondsString:String;

            if (hours > 0)
                hoursString = new String(hours + ":");

            minutes = minutes - (hours * 60);

            if (hours > 0 && minutes < 10)
                minutesString = new String("0" + minutes + ":");
            else
                minutesString = new String(minutes + ":");

            if (seconds < 10)
                secondsString = new String("0" + seconds);
            else
                secondsString = new String(seconds);

            return new String(hoursString + minutesString + secondsString);
        }


        private function deleteInputFile():void {
            var inputFile:File = inputDirectory.resolvePath(inputFileName);

            try {
                inputFile.deleteFile();
            } catch (error:Error) // IOError e SecurityError... pazienza!
            {
                sendToTextArea("\nWARNING: could NOT delete input file " + "\"" + inputFile.nativePath + "\"" + " !");
                sendToTextArea("\nlog file will be saved");
                writeLogFile(false, true);

                return;
            }

            sendToTextArea("\ninput file " + "\"" + inputFile.nativePath + "\"" + " deleted!\n");
        }


        private function writeLogFile(error:Boolean, warning:Boolean):void {
            var logFileName:String;

            if (error) {
                logFileName = new String("ERROR_" + outputFile.name);
            } else {
                logFileName = new String(outputFile.name);
            }

            if (warning) {
                logFileName += "_WARNING_log.txt";
            } else {
                logFileName += "_log.txt";
            }


            // controllo se c'è spazio pure per salvare il log file...!
            if (outputDirectory.spaceAvailable > 64 * 1024) // voglio almeno 64 kB per salvare il log file. in realtà è di 4 kB di solito, ma vogliamo stare larghi.
            {
                var logFile:File = outputDirectory.resolvePath(logFileName);
                var logFileStream:FileStream = new FileStream();
                logFileStream.open(logFile, FileMode.WRITE);
                logFileStream.writeUTFBytes(textArea.text);
                logFileStream.close();

                // scrivere sta roba nel log file stesso non ha senso...
                sendToTextArea("log file saved!");
                sendToTextArea("log file path is: " + "\"" + logFile.nativePath + "\"");
            } else {
                sendToTextArea("\nlog file NOT saved! there is not enough space in \"" + outputDirectory.nativePath + "\"");
            }
        }


        /*
         * USER INTERFACE
         */

        private function addedToStageHandler(event:Event):void {
            // Scaling
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            stage.addEventListener(Event.RESIZE, stageResizeHandler);

            initUserInterface();
        }


        private function stageResizeHandler(event:Event):void {
            resize();
        }

        private function resize():void {
            resizeUserInterface();
        }


        private function initUserInterface():void {
            initProgressBar();

            initButtons();

            initTimer();

            resizeUserInterface();
        }


        private function initProgressBar():void {
            encryptingProgressBar = new ProgressBar();

            encryptingProgressBar.mode = ProgressBarMode.MANUAL;

            encryptingProgressBar.indeterminate = false;

            encryptingProgressBar.minimum = 0;

            encryptingProgressBar.maximum = Number.MAX_VALUE; // totalBytes!

            encryptingProgressBar.height = progressBarHeight;

            encryptingProgressBar.setStyle("barSkin", ProgressBarSkinVerde);

            addChild(encryptingProgressBar);
        }



        private function initButtons():void {
            initProgressPercentFakeButton();

            initEncryptedMBfakeButton(); // up left

            initToEncryptMBfakeButton(); // center left

            initTimeElapsedFakeButton(); // up center

            initTimeRemainingFakeButton(); // center center

            initEncryptionSpeedFakeButton(); // up right

            initDeleteInputFileCheckBox(); // bottom left

            initSaveLogFileCheckBox(); // bottom center

            initCloseOnCompleteCheckBox(); // bottom right
        }


        private function initProgressPercentFakeButton():void {
            progressPercentFakeButton = new Button();

            progressPercentFakeButton.height = buttonHeight;

            progressPercentFakeButton.setStyle("upSkin", Button_upSkin_transparent);

            progressPercentFakeButton.setStyle("downSkin", Button_downSkin_transparent);

            progressPercentFakeButton.setStyle("overSkin", Button_overSkin_transparent);

            progressPercentFakeButton.label = "";

            progressPercentFakeButton.setStyle("textFormat", textFormat);

            addChild(progressPercentFakeButton);
        }


        private function initEncryptedMBfakeButton():void {
            bottomButtonsCounter++;

            encryptedMBfakeButton = new Button();

            encryptedMBfakeButton.height = buttonHeight;

            encryptedMBfakeButton.setStyle("upSkin", Button_upSkin_transparent);

            encryptedMBfakeButton.setStyle("downSkin", Button_downSkin_transparent);

            encryptedMBfakeButton.setStyle("overSkin", Button_overSkin_transparent);

            encryptedMBfakeButton.label = "MegaBytes encrypted =";

            encryptedMBfakeButton.setStyle("textFormat", textFormat);

            addChild(encryptedMBfakeButton);
        }


        private function initToEncryptMBfakeButton():void {
            toEncryptMBfakeButton = new Button();

            toEncryptMBfakeButton.height = buttonHeight;

            toEncryptMBfakeButton.setStyle("upSkin", Button_upSkin_transparent);

            toEncryptMBfakeButton.setStyle("downSkin", Button_downSkin_transparent);

            toEncryptMBfakeButton.setStyle("overSkin", Button_overSkin_transparent);

            toEncryptMBfakeButton.label = "MegaBytes to encrypt =";

            toEncryptMBfakeButton.setStyle("textFormat", textFormat);

            addChild(toEncryptMBfakeButton);
        }


        private function initTimeElapsedFakeButton():void {
            bottomButtonsCounter++;

            timeElapsedFakeButton = new Button();

            timeElapsedFakeButton.height = buttonHeight;

            timeElapsedFakeButton.setStyle("upSkin", Button_upSkin_transparent);

            timeElapsedFakeButton.setStyle("downSkin", Button_downSkin_transparent);

            timeElapsedFakeButton.setStyle("overSkin", Button_overSkin_transparent);

            timeElapsedFakeButton.label = "time elapsed =";

            timeElapsedFakeButton.setStyle("textFormat", textFormat);

            addChild(timeElapsedFakeButton);
        }


        private function initTimeRemainingFakeButton():void {
            timeRemainingFakeButton = new Button();

            timeRemainingFakeButton.height = buttonHeight;

            timeRemainingFakeButton.setStyle("upSkin", Button_upSkin_transparent);

            timeRemainingFakeButton.setStyle("downSkin", Button_downSkin_transparent);

            timeRemainingFakeButton.setStyle("overSkin", Button_overSkin_transparent);

            timeRemainingFakeButton.label = "time remaining =";

            timeRemainingFakeButton.setStyle("textFormat", textFormat);

            addChild(timeRemainingFakeButton);
        }


        private function initEncryptionSpeedFakeButton():void {
            bottomButtonsCounter++;

            encryptionSpeedFakeButton = new Button();

            encryptionSpeedFakeButton.height = buttonHeight;

            encryptionSpeedFakeButton.setStyle("upSkin", Button_upSkin_transparent);

            encryptionSpeedFakeButton.setStyle("downSkin", Button_downSkin_transparent);

            encryptionSpeedFakeButton.setStyle("overSkin", Button_overSkin_transparent);

            encryptionSpeedFakeButton.label = "encryption speed =";

            encryptionSpeedFakeButton.setStyle("textFormat", textFormat);

            addChild(encryptionSpeedFakeButton);
        }


        private function initDeleteInputFileCheckBox():void {
            deleteInputFileCheckBox = new CheckBox();

            deleteInputFileCheckBox.selected = false;

            deleteInputFileCheckBox.height = buttonHeight;

            deleteInputFileCheckBox.label = "delete input file";

            deleteInputFileCheckBox.setStyle("textFormat", textFormat);

            addChild(deleteInputFileCheckBox);
        }


        private function initSaveLogFileCheckBox():void {
            saveLogFileCheckBox = new CheckBox();

            saveLogFileCheckBox.selected = true;

            saveLogFileCheckBox.height = buttonHeight;

            saveLogFileCheckBox.label = "save log file";

            saveLogFileCheckBox.setStyle("textFormat", textFormat);

            addChild(saveLogFileCheckBox);
        }


        private function initCloseOnCompleteCheckBox():void {
            closeOnCompleteCheckBox = new CheckBox();

            closeOnCompleteCheckBox.selected = true;

            closeOnCompleteCheckBox.height = buttonHeight;

            closeOnCompleteCheckBox.label = "close when done";

            closeOnCompleteCheckBox.setStyle("textFormat", textFormat);

            addChild(closeOnCompleteCheckBox);
        }


        private function initTimer():void {
            timer = new Timer(timerUpdateInterval);

            timer.addEventListener(TimerEvent.TIMER, timerHandler);

            timer.start(); // fondamentale farlo partire!
        }


        private function timerHandler(event:TimerEvent):void {
            updateUserInterface();
        }


        private function updateUserInterface():void {
            updateProgressBar();
            updateProgressPercentFakeButton();
            updateEncryptedMBfakeButton();
            updateToEncryptMBfakeButton();
            updateTimeElapsedFakeButton();
            updateEncryptionSpeedFakeButton();
            updateTimeRemainingFakeButton();
        }


        private function updateProgressBar():void {
            encryptingProgressBar.setProgress(encryptedBytes, inputFileSizeInBytes);
        }


        private function updateProgressPercentFakeButton():void {
            progressPercentFakeButton.label = new String(encryptingProgressBar.percentComplete.toFixed(0) + "%");
        }


        private function updateEncryptedMBfakeButton():void {
            encryptedMBfakeButton.label = new String("MegaBytes encrypted = " + encryptedMegaBytes.toFixed(2));
        }


        private function updateToEncryptMBfakeButton():void {
            var remainingMB:Number = inputFileSizeInMegaBytes - encryptedMegaBytes;

            if (remainingMB <= 0)
                remainingMB = 0; // per la differenza tra block size before e after encryption, alla fine verrebbe un numero negativo, ma vogliamo comunque mostrare 0!

            toEncryptMBfakeButton.label = new String("MegaBytes to encrypt = " + remainingMB.toFixed(2));
        }


        private function updateTimeElapsedFakeButton():void {
            timeElapsedFakeButton.label = new String("time elapsed = " + getTimeString(getTimer() / 1000));
        }


        private function updateEncryptionSpeedFakeButton():void {
            encryptedBytesPerSecond = encryptedBytes - encryptedBytesAtPreviousUpdate;

            encryptedBytesAtPreviousUpdate = encryptedBytes;

            var encryptedMBfromLastUpdate:Number;
            encryptedMBfromLastUpdate = encryptedBytesPerSecond / (1024 * 1024);

            encryptionSpeedFakeButton.label = new String("encryption speed = " + encryptedMBfromLastUpdate.toFixed(2) + " MB/s");

            // nota che tutto ciò ha senso perché l'aggiornamento del timer è di UN secondo...!!!
        }


        private function updateTimeRemainingFakeButton():void {
            var toEncryptBytes:uint = inputFileSizeInBytes - encryptedBytes;

            var secondsToComplete:uint = toEncryptBytes / encryptedBytesPerSecond;

            timeRemainingFakeButton.label = new String("time remaining = " + getTimeString(secondsToComplete));
        }


        private function resizeUserInterface():void {
            // ordine fondamentale!!!
            buttonWidth = stage.stageWidth / bottomButtonsCounter;

            resizeProgressBar();

            resizeButtons();

            resizeTextArea();
        }


        private function resizeProgressBar():void {
            encryptingProgressBar.width = stage.stageWidth;

            encryptingProgressBar.move(0, stage.stageHeight - bottomUIpanelHeight);
        }


        private function resizeButtons():void {
            resizeProgressPercentFakeButton();

            resizeEncryptedMBfakeButton();

            resizeToEncryptMBfakeButton();

            resizeTimeElapsedFakeButton();

            resizeTimeRemainingFakeButton();

            resizeEncryptionSpeedFakeButton();

            resizeDeleteInputFileCheckBox();

            resizeSaveLogFileCheckBox();

            resizeCloseOnCompleteCheckBox();
        }


        private function resizeProgressPercentFakeButton():void {
            progressPercentFakeButton.width = stage.stageWidth;

            progressPercentFakeButton.move(0, stage.stageHeight - bottomUIpanelHeight);
        }


        private function resizeEncryptedMBfakeButton():void {
            encryptedMBfakeButton.width = buttonWidth;

            encryptedMBfakeButton.move(0, stage.stageHeight - buttonHeight * 3);
        }


        private function resizeToEncryptMBfakeButton():void {
            toEncryptMBfakeButton.width = buttonWidth;

            toEncryptMBfakeButton.move(0, stage.stageHeight - buttonHeight * 2);
        }


        private function resizeTimeElapsedFakeButton():void {
            timeElapsedFakeButton.width = buttonWidth;

            timeElapsedFakeButton.move(encryptedMBfakeButton.width, stage.stageHeight - buttonHeight * 3);
        }


        private function resizeTimeRemainingFakeButton():void {
            timeRemainingFakeButton.width = buttonWidth;

            timeRemainingFakeButton.move(toEncryptMBfakeButton.width, stage.stageHeight - buttonHeight * 2);
        }


        private function resizeEncryptionSpeedFakeButton():void {
            encryptionSpeedFakeButton.width = buttonWidth;

            encryptionSpeedFakeButton.move(encryptedMBfakeButton.width + timeElapsedFakeButton.width, stage.stageHeight - buttonHeight * 3);
        }


        private function resizeDeleteInputFileCheckBox():void {
            deleteInputFileCheckBox.width = buttonWidth;

            deleteInputFileCheckBox.move(0, stage.stageHeight - buttonHeight);
        }


        private function resizeSaveLogFileCheckBox():void {
            saveLogFileCheckBox.width = buttonWidth;

            saveLogFileCheckBox.move(deleteInputFileCheckBox.width, stage.stageHeight - buttonHeight);
        }


        private function resizeCloseOnCompleteCheckBox():void {
            closeOnCompleteCheckBox.width = buttonWidth;

            closeOnCompleteCheckBox.move(deleteInputFileCheckBox.width + saveLogFileCheckBox.width, stage.stageHeight - buttonHeight);
        }


        private function resizeTextArea():void {
            textArea.width = stage.stageWidth;

            textArea.height = stage.stageHeight - bottomUIpanelHeight;
        }


    } // class closed
} // package closed
