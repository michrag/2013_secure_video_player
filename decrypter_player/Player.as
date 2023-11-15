package {
    /**
     * PLAYER WORKER
     */

    import fl.controls.*;
    import fl.events.SliderEvent;
    import flash.display.LoaderInfo;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageDisplayState;
    import flash.display.StageScaleMode;
    import flash.errors.MemoryError;
    import flash.events.*;
    import flash.external.ExternalInterface;
    import flash.geom.Rectangle;
    import flash.media.SoundTransform;
    import flash.media.StageVideo;
    import flash.media.StageVideoAvailability;
    import flash.media.Video;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.NetStreamAppendBytesAction;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.net.URLRequestMethod;
    import flash.net.URLStream;
    import flash.system.Capabilities;
    import flash.system.MessageChannel;
    import flash.system.Security;
    import flash.system.System;
    import flash.system.Worker;
    import flash.system.WorkerDomain;
    import flash.system.WorkerState;
    import flash.ui.Keyboard;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.Timer;
    import flash.text.TextFormat;


    public class Player extends Sprite {
        // GLOBAL VARIABLES

        // FONDAMENTALI
        private var videoURL:String;
        private var urlRequest:URLRequest;
        private var urlStream:URLStream;
        private var netConnection:NetConnection;
        private var netStream:NetStream;
        private var video:Video; // classic aka legacy video ("backup" per StageVideo)

        // video info (retrieved from metadata)
        private var videoTotalTimeSeconds:Number = 0; // default NaN, mi serve se netstream buffer empty
        private var videoTotalTimeString:String;
        private var videoFileTotalSizeBytes:uint;
        // counters per progress bars
        private var bytesDownloaded:uint;
        private var bytesDecrypted:uint;


        // WORKERS
        [Embed(source = "../bin/Decrypter.swf", mimeType = "application/octet-stream")]
        private static var decrypterWorkerByteClass:Class;
        private var decrypterWorker:Worker;
        // workers message channels
        // debugging
        private var playerToDecrypterDebuggingMsgChl:MessageChannel;
        private var decrypterToPlayerDebuggingMsgChl:MessageChannel;
        // startup
        private var playerToDecrypterInitMsgChl:MessageChannel; // passa al decrypter algoritmo, block size e chiave
        private var decrypterToPlayerReadyMsgChl:MessageChannel; // (ready signal from decrypter to player)
        // progressing
        private var playerToDecrypterProgressingMsgChl:MessageChannel;
        private var decrypterToPlayerProgressingMsgChl:MessageChannel;
        // complete (stream download compete from player to decrypter)
        private var playerToDecrypterCompleteMsgChl:MessageChannel;

        private var bruteForceStopSignal:ByteArray;


        // STAGE VIDEO
        private var stageVideo:StageVideo;
        private var stageVideoAvailable:Boolean;
        private var stageVideoRunning:Boolean;


        // SEEK
        private var playingOrPausedVideo:Boolean;
        private var tagsTable:Array;
        private var seekBytePosition:int; // int perché le tagPosition sono int, e le tagPosition sono int perché devono poter essere < 0
        private var decryptedVideo:ByteArray;
        private var seekedVideo:ByteArray;
        private var playTimeSeconds:Number = 0; // default NaN, mi serve se netstream buffer empty
        private var seekTimeSeconds:Number;
        private var decryptedVideoStartsAtTheBeginningOfTheSourceVideo:Boolean;
        private var decryptedVideoStartsAtAValidTagPosition:Boolean;
        private var cumulativeTagPositionOffset:int;


        // UI
        private var textFormat:TextFormat;
        private const stageColor:uint = 0x000000; // paint it black!
        // pulsanti (e volume slider)
        private const buttonHeight:uint = 30;
        private const progressBarHeight:uint = 15;
        private const bottomUIpanelHeight:uint = buttonHeight + progressBarHeight;

        private var buttonWidth:uint; // questa invece è variabile!
        private var bottomButtonsCounter:int; // per fare i pulsanti con la stessa larghezza
        private var fakeTimeButton:Button; // pulsante finto usato per mostrare i tempi
        private var playPauseButton:Button;
        private var stopButton:Button;
        private var fakeVolumeButton:Button; // pulsante finto che fa da sfondo al volume slider
        private var volumeSlider:Slider;
        private var volumeTransform:SoundTransform;
        private var fullScreenButton:Button;
        private var bruteForceStopButton:Button;
        private var stageVideoButton:Button;
        private var debugTextArea:TextArea;
        private var forbiddenTextArea:TextArea;

        // progress bars
        private var fakeBackgroundProgressBar:ProgressBar;
        private var downloadProgressBar:ProgressBar;
        private var decryptingProgressBar:ProgressBar;
        private var playProgressBar:ProgressBar;
        private var timer:Timer;
        private const timerUpdateInterval:uint = 500; // millisecondi

        //label dei pulsanti costanti
        private const fakeTimeButtonDefaultLabel:String = "loading...";
        private const fakeTimeButtonIOerrorLabel:String = "streaming error";
        private const fakeTimeButtonSecurityErrorLabel:String = "security error";
        private const playPauseButtonPlayLabel:String = "play";
        private const playPauseButtonPauseLabel:String = "pause";
        private const stopButtonLabel:String = "stop";
        private const fakeVolumeButtonLabel:String = "volume";
        private const fullScreenButtonGoFullScreenLabel:String = "full screen";
        private const fullScreenButtonExitFullScreenLabel:String = "exit full screen";
        private const bruteForceStopButtonLabel:String = "brute force stop";
        private const stageVideoButtonDefaultLabel:String = "StageVideo available: ? \n StageVideo running: ?";

        // campi metadata costanti
        // keyframes, "iniettato" da flvmdi o YAMDI, è un Object composto da 2 array che si chiamano uno "times" e l'altro "filepositions"
        private const tagsTableMetaDataName:String = "keyframes";
        private const tagsTableMetaDataTimesName:String = "times";
        private const tagsTableMetaDataPositionsName:String = "filepositions";

        // info sicure passare a runtime!
        private var encryptionAlgorithm:String;
        private var decryptionBufferSize:uint;
        private var cryptoKeyString:String;
        private var keysProviderURL:String;


        // DEBUG vars (default values are false)
        private var debug:Boolean; // debug purpose; default is false
        private var plainVideo:Boolean; // per fare debug con un video in chiaro (non cifrato)
        private var traceTagsTable:Boolean; // debug purpose


        // CONSTRUCTOR
        public function Player() {
            //trace(Capabilities.version);

            volumeTransform = new SoundTransform(1); // volume di default: 50%

            LoaderInfo(this.root.loaderInfo).addEventListener(Event.COMPLETE, loaderCompleteHandler);

            // STAGE VIDEO: Make sure the app is visible and stage available
            addEventListener(Event.ADDED_TO_STAGE, addedToStageHandler);

            // per far sì che quando viene lasciata la pagina nel browser venga chiamata bruteForceStop
            flash.system.Security.allowDomain("*"); // questo ha risolto il problema JS => as3....!!!

            if (ExternalInterface.available) // è true!
            {
                //ExternalInterface.marshallExceptions = true; // di default è false
                // "fromJavaScript" è il nome che ha nell'html/php (quindi andrebbe cambiato nome anche di là!), "calledFromJS" è il nome che ha qui nel codice!!!
                ExternalInterface.addCallback("fromJavaScript", calledFromJavaScript);
            } else {
                sendToTextArea("External Interface NOT available"); // se non available riceverei errore nel flash player debug version perché la textArea ancora non l'ho creata!
            }
        }


        private function calledFromJavaScript(val:Boolean):void {
            if (bruteForceStopSignal != null) // i.e. il video era in riproduzione
            {
                bruteForceStop();
            } else // in pratica, il video non era partito perché l'utente non era autorizzato
            {
                // do nothing...!
            }
        }


        private function loaderCompleteHandler(e:Event):void {
            sendToTextArea("loaderCompleteHandler");

            /* <param name="FlashVars" value="videoURL=AdobeMerdaEsplodiTiOdio" /> // nell'html
             * per passarne più di una: FlashVars="myVariable=Hello%20World&mySecondVariable=Goodbye"
             * You can pass as many variables as you want with any variable names that you want. All browsers support FlashVars strings of up to 64 KB (65535 bytes) in length.
             * The format of the FlashVars property is a string that is a set of name=value pairs separated by the '&' character.
             */

            var flashVars:Object = LoaderInfo(this.root.loaderInfo).parameters;

            //sendToTextArea(paramObj.toString());

            for (var flashVar:* in flashVars)
                sendToTextArea(flashVar.toString());

            // i nomi delle flashVars (flashVars.<name>) sono determinati dall'html (o php) in cui è inserito l'swf!!!
            videoURL = flashVars.videoURL;
            sendToTextArea("videoURL = " + videoURL); // in realtà funziona, ma in teoria qui non sono sicuro che la textArea esista...!!! pazienza, solo per debug

            keysProviderURL = flashVars.keysProviderURL;
            sendToTextArea("keysProviderURL = " + keysProviderURL);
            getKeyFromKeysProvider(keysProviderURL);
        }


        private function getKeyFromKeysProvider(keyServerURL:String):void {
            // TODO try catchare...?!
            var keyURLrequest:URLRequest = new URLRequest(keyServerURL);
            keyURLrequest.method = URLRequestMethod.GET; // comunque GET è di default!

            var keyURLloader:URLLoader = new URLLoader();
            keyURLloader.addEventListener(Event.COMPLETE, keyURLloaderCompleteHandler);
            keyURLloader.dataFormat = URLLoaderDataFormat.TEXT;
            keyURLloader.load(keyURLrequest);
        }


        private function keyURLloaderCompleteHandler(event:Event):void {
            sendToTextArea("keyURLloaderCompleteHandler --------------------");

            //cryptoKeyString = event.target.data;

            sendToTextArea("key received from keys provider = " + event.target.data); // questa stringa sono le info sicure del video

            if ((event.target.data).length > 0) {
                initSecretInfos(event.target.data);
                startPlayback(); // chiama initDecrypterWorker() e initNetConnectionAndStream()
            } else {
                // TODO gestire un po' meglio...?!
                sendToTextArea("YOU ARE NOT AUTHORIZED FOR THIS VIDEO!");
                fakeTimeButton.label = "not authorized";
                showForbiddenMessage();
                playPauseButton.enabled = false;
                stopButton.enabled = false;
                volumeSlider.enabled = false;

                if (debug)
                    bruteForceStopButton.enabled = false;
            }
        }


        private function showForbiddenMessage():void {
            forbiddenTextArea = new TextArea();

            forbiddenTextArea.editable = false;
            forbiddenTextArea.wordWrap = false;

            var forbiddenTextFormat:TextFormat = new TextFormat();
            forbiddenTextFormat.font = "Kalinga"; // "Kalinga" o "Courier New"
            forbiddenTextFormat.size = 48;
            forbiddenTextFormat.align = "center";
            forbiddenTextFormat.bold = true;

            forbiddenTextArea.setStyle("textFormat", forbiddenTextFormat);

            forbiddenTextArea.text = "\nFORBIDDEN";

            addChild(forbiddenTextArea);

            forbiddenTextArea.width = stage.stageWidth / 4;

            forbiddenTextArea.height = stage.stageHeight / 4;

            forbiddenTextArea.move(stage.stageWidth / 2 - forbiddenTextArea.width / 2, stage.stageHeight / 2 - forbiddenTextArea.width / 2);

        }


        private function initSecretInfos(secretString:String):void {
            // secretString deve essere della forma algId&bufferSize&secretKey
            // dove algId = 1 => AES 128, 2=> 192, 3=> 256 bit (key size)
            var secretInfos:Array = secretString.split("&");

            switch (uint(secretInfos[0])) {
                case 1:
                    encryptionAlgorithm = "simple-aes128-cbc";
                    break;

                case 2:
                    encryptionAlgorithm = "simple-aes192-cbc";
                    break;

                case 3:
                    encryptionAlgorithm = "simple-aes256-cbc";
                    break;
            }

            decryptionBufferSize = uint(secretInfos[1]);

            cryptoKeyString = secretInfos[2];
        }


        private function startPlayback():void {
            decryptedVideo = new ByteArray();
            seekedVideo = new ByteArray();
            tagsTable = new Array();

            bytesDownloaded = 0;
            bytesDecrypted = 0;
            seekBytePosition = 0;
            playTimeSeconds = 0;
            seekTimeSeconds = 0;
            cumulativeTagPositionOffset = 0;

            playingOrPausedVideo = true;
            decryptedVideoStartsAtTheBeginningOfTheSourceVideo = true;
            decryptedVideoStartsAtAValidTagPosition = true;

            initDecrypterWorker();

            initNetConnectionAndStream();

            toggleStageLegacyVideo(stageVideoAvailable); // se dopo bruteforcestop...
        }


        private function initNetConnectionAndStream():void {
            netConnection = new NetConnection(); // The NetConnection class creates a two-way connection between a client and a server
            netConnection.connect(null); // Pass "null" to play video and mp3 files from a local file system or from a web server

            netStream = new NetStream(netConnection); // The NetStream class opens a one-way streaming channel over a NetConnection

            netStream.addEventListener(NetStatusEvent.NET_STATUS, netStreamNetStatusEventHandler);

            netStream.client = this; // ok per onMetaData ma no per onSeekPoint.

            // come sotto invece andava bene anche per onSeekPoint, ma tanto non funziona...!
            //netStream.client = {}; 
            //netStream.client.onMetaData = this.onMetaData;
            //netStream.client.onSeekPoint = this.onSeekPoint; 

            netStream.play(null); // Call play(null) to enable "Data Generation Mode". In this mode, call the appendBytes() method to deliver data to the NetStream

            //trace("netstream inited");

            netStream.soundTransform = volumeTransform;
        }


        private function netStreamNetStatusEventHandler(event:NetStatusEvent):void {
            //trace(event.info.toString());

            switch (event.info.code) {
                case "NetStream.Seek.Notify": //Capture the "NetStream.Seek.Notify" event to call appendBytesAction() after a seek
                    /*
                     * The seek operation is complete.
                     * Sent when NetStream.seek() is called on a stream in AS3 NetStream Data Generation Mode.
                     * The info object is extended to include info.seekPoint which is the same value passed to NetStream.seek().
                     */

                    //trace("NetStream.Seek.Notify");

                    /*
                     * To seek, at the event NetStream.Seek.Notify, find the bytes that start at a seekable point and
                     * call appendBytes(bytes). If the bytes argument is a ByteArray consisting of bytes starting at
                     * the seekable point, the video plays at that seek point.
                     */
                    playVideoAtSeekPosition();
                    break;

                //case "NetStream.Play.Stop": // non viene generato!
                case "NetStream.Buffer.Empty":
                    // viene sicuramente generato quando il video arriva in fondo, ma viene generato anche prima (di solito all'inizio)
                    // perciò controllo se il video è effettivamente alla fine (con un margine perché sto confrontando due Number, difficile siano esattamente uguali!)
                    if (videoTotalTimeSeconds > 0 && Math.abs(videoTotalTimeSeconds - playTimeSeconds) < videoTotalTimeSeconds / 100) {
                        pauseAndSeekToTheBeginningOfDecryptedVideo();
                    }
                    //sendToTextArea("NetStream.Buffer.Empty !!!");
                    break;

                case "NetStream.Buffer.Flush": // non viene generato!
                    //pauseAndSeekToTheBeginningOfDecryptedVideo();
                    //sendToTextArea("NetStream.Buffer.FLUSH !!!");
                    break;
            }
        }


        // WORKERS...
        private function initDecrypterWorker():void {
            if (Worker.isSupported)
                trace("Worker supported");
            else
                trace("Worker is NOT supported");

            // create the background worker
            var decrypterWorkerBytes:ByteArray = new decrypterWorkerByteClass();

            if (decrypterWorkerBytes == null)
                trace("decrypterWorkerBytes is null");

            decrypterWorker = WorkerDomain.current.createWorker(decrypterWorkerBytes);

            if (decrypterWorker == null)
                trace("decrypterWorker is null");

            initWorkersMessageChannels();

            // start decrypter worker
            decrypterWorker.addEventListener(Event.WORKER_STATE, decrypterWorkerStateHandler);
            decrypterWorker.start();
        }


        private function decrypterWorkerStateHandler(event:Event):void {
            if (decrypterWorker.state == WorkerState.RUNNING) {
                trace("Decrypter worker started (\"running\")");
            }
        }


        private function initWorkersMessageChannels():void {
            // player to decrypter
            // debugging
            playerToDecrypterDebuggingMsgChl = Worker.current.createMessageChannel(decrypterWorker);
            decrypterWorker.setSharedProperty("playerToDecrypterDebuggingMsgChl", playerToDecrypterDebuggingMsgChl);
            // init msgChl player -> decrypter con cui gli passo un object (alg, buffer-aka-block size, key)
            playerToDecrypterInitMsgChl = Worker.current.createMessageChannel(decrypterWorker);
            decrypterWorker.setSharedProperty("playerToDecrypterInitMsgChl", playerToDecrypterInitMsgChl);
            // progressing
            playerToDecrypterProgressingMsgChl = Worker.current.createMessageChannel(decrypterWorker);
            decrypterWorker.setSharedProperty("playerToDecrypterProgressingMsgChl", playerToDecrypterProgressingMsgChl);
            // complete
            playerToDecrypterCompleteMsgChl = Worker.current.createMessageChannel(decrypterWorker);
            decrypterWorker.setSharedProperty("playerToDecrypterCompleteMsgChl", playerToDecrypterCompleteMsgChl);

            // decrypter to player
            // debugging
            decrypterToPlayerDebuggingMsgChl = decrypterWorker.createMessageChannel(Worker.current);
            decrypterToPlayerDebuggingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onDebuggingMessageFromDecrypter);
            decrypterWorker.setSharedProperty("decrypterToPlayerDebuggingMsgChl", decrypterToPlayerDebuggingMsgChl);
            // startup
            decrypterToPlayerReadyMsgChl = decrypterWorker.createMessageChannel(Worker.current);
            decrypterToPlayerReadyMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onStartupMessageFromDecrypter);
            decrypterWorker.setSharedProperty("decrypterToPlayerReadyMsgChl", decrypterToPlayerReadyMsgChl);
            // progressing
            decrypterToPlayerProgressingMsgChl = decrypterWorker.createMessageChannel(Worker.current);
            decrypterToPlayerProgressingMsgChl.addEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromDecrypter);
            decrypterWorker.setSharedProperty("decrypterToPlayerProgressingMsgChl", decrypterToPlayerProgressingMsgChl);


            bruteForceStopSignal = new ByteArray();
            bruteForceStopSignal[0] = false;
            bruteForceStopSignal.shareable = true;
            decrypterWorker.setSharedProperty("bruteForceStopSignal", bruteForceStopSignal);
        }


        private function closeAllMessageChannels():void {
            // player to decrypter
            // debugging
            playerToDecrypterDebuggingMsgChl.close();
            // init msgChl player -> decrypter con cui gli passo un object (alg, buffer-aka-block size, key)
            playerToDecrypterInitMsgChl.close();
            // progressing
            playerToDecrypterProgressingMsgChl.close();
            // complete
            playerToDecrypterCompleteMsgChl.close();

            // decrypter to player
            // debugging
            decrypterToPlayerDebuggingMsgChl.close();
            // startup
            decrypterToPlayerReadyMsgChl.close();
            // progressing
            decrypterToPlayerProgressingMsgChl.close();
        }


        private function onDebuggingMessageFromDecrypter(ev:Event):void {
            if (debug) {
                var message:String = decrypterToPlayerDebuggingMsgChl.receive();
                trace("Message from decrypter:", message);
                sendToTextArea("Message from decrypter: " + message);
            }
        }


        private function onStartupMessageFromDecrypter(ev:Event):void {
            var decrypterWorkerReady:Boolean = decrypterToPlayerReadyMsgChl.receive() as Boolean;
            if (decrypterWorkerReady) {
                //trace("Decrypter worker ready");

                // gli passo le info sicure
                // object = {name1 : value1, name2 : value2,... nameN : valueN} Creates a new object and initializes it with the specified name and value property pairs
                playerToDecrypterInitMsgChl.send({algorithm: encryptionAlgorithm, bufferSize: decryptionBufferSize, key: cryptoKeyString});

                initUrlRequestAndStream();
            } else {
                trace("decrypter worker failed to startup!");
            }
        }


        private function initUrlRequestAndStream():void {
            /*
               The URLRequest class captures all of the information in a single HTTP request.
               URLRequest objects are passed to the load() methods of the URLStream class to initiate URL downloads
             */
            urlRequest = new URLRequest(videoURL);

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

            if (!debug)
                urlStream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, urlStreamSecurityErrorHandler);
        }


        private function urlStreamOpenHandler(event:Event):void {
            //trace("URL Stream opened");

            playerToDecrypterDebuggingMsgChl.send("URL Stream opened");
        }


        private function urlStreamCompleteHandler(event:Event):void {
            //trace("URL Stream completed: " + event);

            if (!plainVideo) {
                playerToDecrypterCompleteMsgChl.send(true);
            }
        }


        private function urlStreamHttpStatusHandler(event:HTTPStatusEvent):void {
            //trace("urlStream http Status:", event.toString());
        }


        private function urlStreamIOerrorHandler(event:IOErrorEvent):void {
            //trace("urlStream IO error:", event.toString());
            fakeTimeButton.label = fakeTimeButtonIOerrorLabel;
        }


        private function urlStreamSecurityErrorHandler(event:SecurityErrorEvent):void {
            //trace("urlStream Security Error:", event);
            fakeTimeButton.label = fakeTimeButtonSecurityErrorLabel;
        }


        private function urlStreamProgressHandler(event:ProgressEvent):void {
            var downloadedBytes:ByteArray;
            downloadedBytes = new ByteArray();
            downloadedBytes.shareable = true; // passaggio per riferimento! (più veloce, meno memoria!)

            urlStream.readBytes(downloadedBytes); // leggo tutti quelli disponibili!

            bytesDownloaded = bytesDownloaded + downloadedBytes.length; // aggiorno il contatore

            if (!plainVideo) {
                // coda ILLIMITATA altrimenti fail! 
                playerToDecrypterProgressingMsgChl.send(downloadedBytes); // lo passo al decrypter
            } else // video in chiaro (debug)
            {
                progressivePlay(downloadedBytes);
                bytesDecrypted = bytesDownloaded; // così la barra verde appare anche se il video è in chiaro!
            }

        }


        private function onProgressingMessageFromDecrypter(ev:Event):void {
            if (bruteForceStopSignal[0] == false) {
                var decryptedBuffer:ByteArray = decrypterToPlayerProgressingMsgChl.receive(); //lo ricevo

                if (playingOrPausedVideo) // così in caso di bruteforcestop la progress bar non avanza...
                    bytesDecrypted = bytesDecrypted + decryptedBuffer.length; // aggiorno il contatore

                progressivePlay(decryptedBuffer);

                decryptedBuffer.clear(); // fondamentale per non sprecare memoria
                    //trace("decryptedBuffer.length =", decryptedBuffer.length); // ok stampa 0, lo elimina davvero
            } else {
                decrypterToPlayerProgressingMsgChl.removeEventListener(Event.CHANNEL_MESSAGE, onProgressingMessageFromDecrypter);
            }
        }


        private function progressivePlay(bytes:ByteArray):void {
            try {
                decryptedVideo.writeBytes(bytes); // per poter seekare... Ma raddoppia la memoria usata.
            } catch (e:MemoryError) {
                if (debug) {
                    trace("MemoryError trying to write decryptedVideo");
                    trace(e);
                    trace("FALSE: the system is plenty of memory, but Adobe Flash Player can't handle it!");
                    debugTraceMemoryInfo();
                }

                var tagPositionOffset:int = decryptedVideo.length;

                cumulativeTagPositionOffset += tagPositionOffset;
                // se ancora non ho costruito la tagTable (perché non ho ancora ricevuto i metaData)
                // appena costruita la aggiornerà con il cumulativeTagPositionOffset

                decryptedVideo.clear();

                decryptedVideoStartsAtTheBeginningOfTheSourceVideo = false;

                decryptedVideoStartsAtAValidTagPosition = false;

                if (debug) {
                    debugForceGarbageCollection();
                    debugTraceMemoryInfo();
                }

                decryptedVideo.writeBytes(bytes); // fondamentale! (adesso è sicuro farlo)

                spliceTagsTable(tagPositionOffset);
            }

            netStream.appendBytes(bytes);

            // NOTA che in questo modo il seek funziona perfettamente!!! quado seeko, flusho il playout buffer e ci metto
            // il decryptedVideo (fin dove ce l'ho). poi appena mi arriva un altro pezzo decifrato, lo aggiungo al
            // playout buffer (appendBytes), così il video andrà avanti come se nulla fosse!!! ...Non era affatto scontato!!!

            //if ( !decryptedVideoStartsAtAValidTagPosition && getTagsTableFirstValidIndex() != -1 )
            if (!decryptedVideoStartsAtAValidTagPosition && tagsTable.length > 0) {
                shiftLeftDecryptedVideoSoThatItStartsAtAValidTagPosition();
            }

            //updatePlayTime();
        }


        // chi la chiama è sicuro che la tagsTable sia NON vuota...!!!
        private function shiftLeftDecryptedVideoSoThatItStartsAtAValidTagPosition():void {
            //trace("shiftLeftDecryptedVideoSoThatItStartsAtAValidTagPosition");

            var offset:int = tagsTable[0].tagPosition; // questo offset NON lo devo sommare al cumulativeTagPositionOffset!

            //trace("decryptedVideo.length =", decryptedVideo.length);
            //trace("offset =", offset);

            if (decryptedVideo.length > offset) {
                var tmpBytes:ByteArray = new ByteArray();

                tmpBytes.writeBytes(decryptedVideo, offset);

                decryptedVideo.clear();

                decryptedVideo.writeBytes(tmpBytes);

                tmpBytes.clear();

                spliceTagsTable(offset);

                decryptedVideoStartsAtAValidTagPosition = true;

                    //trace("decryptedVideoStartsAtAValidTagPosition =", decryptedVideoStartsAtAValidTagPosition);
            }
        }


        public function onMetaData(metaDataObject:Object):void {
            var timeElapsed:int = getTimer();

            videoTotalTimeSeconds = metaDataObject.duration;

            videoTotalTimeString = getTimeString(videoTotalTimeSeconds);

            videoFileTotalSizeBytes = metaDataObject.filesize;

            downloadProgressBar.maximum = videoFileTotalSizeBytes;
            decryptingProgressBar.maximum = videoFileTotalSizeBytes;
            playProgressBar.maximum = videoTotalTimeSeconds;

            //trace("metadata: duration s=" + info.duration + "; width=" + info.width + "; height=" + info.height + "; framerate=" + info.framerate);
            //trace("time elapsed when metadata received (ms) =", timeElapsed);

            buildTagsTable(metaDataObject);

            timer.start(); // fondamentale farlo partire! lo faccio partire qui perché prima non ha senso / è inutile / forse dannoso
        }


        private function getTimeString(totalSeconds:int):String {
            var hours:int = totalSeconds / (60 * 60);
            var minutes:int = totalSeconds / 60;
            var seconds:int = totalSeconds % 60;

            var hoursString:String = new String();
            var minutesString:String;
            var secondsString:String;

            // se il total time ha le ore, voglio che anche il playing time abbia le ore!!
            if (hours > 0 || videoTotalTimeSeconds >= 60 * 60)
                hoursString = new String(hours + ":");

            minutes = minutes - (hours * 60);

            if ((hours > 0 || videoTotalTimeSeconds >= 60 * 60) && minutes < 10)
                minutesString = new String("0" + minutes + ":");
            else
                minutesString = new String(minutes + ":");

            if (seconds < 10)
                secondsString = new String("0" + seconds);
            else
                secondsString = new String(seconds);

            return new String(hoursString + minutesString + secondsString);
        }


        // costruisce la tags table (time in seconds of keyframe - byte position of keyframe)
        private function buildTagsTable(metaDataObject:Object):void {
            //trace("---------- START of metadata values ----------");
            for (var valueName:String in metaDataObject) {
                var value:Object = metaDataObject[valueName];

                //trace(valueName + " = " + value);

                if (valueName == tagsTableMetaDataName) {
                    //trace(tagsTableMetaDataName + " metadata found! :)");

                    for (var subValue:Object in value) {
                        //trace(" " + subValue.toString());
                    }

                    var timesArray:Array = value[tagsTableMetaDataTimesName];
                    var filepositionsArray:Array = value[tagsTableMetaDataPositionsName];

                    for (var i:int = 0; i < timesArray.length; i++) {
                        var time:Number = timesArray[i]; // time è l'istante temporale, in secondi, a cui si trova il keyframe
                        var fileposition:int = filepositionsArray[i]; // fileposition è la posizione, in byte, a cui si trova il keyframe
                        // NOTA: è un int (e non uint) perché poi potrebbe assumere valori negativi! tanto un file più grosso di 2 GB fa esplodere tutto comunque!
                        tagsTable.push({tagTime: time, tagPosition: fileposition}); // object = {name1 : value1, name2 : value2,... nameN : valueN} Creates a new object and initializes it with the specified name and value property pairs
                    }

                    if (debug && traceTagsTable) {
                        debugTraceTagsTable();
                    }
                }
            }
            //trace("--------- END of metadata values ----------");

            // se sono sfigato e il decryptedVideo è esploso (magari più volte) prima di averla costruita...

            spliceTagsTable(cumulativeTagPositionOffset);

            //if ( !decryptedVideoStartsAtAValidTagPosition )
            if (!decryptedVideoStartsAtAValidTagPosition && tagsTable.length > 0) {
                shiftLeftDecryptedVideoSoThatItStartsAtAValidTagPosition();
            }
        }

        // sottrae offset a tutte le position della tagsTable poi rimuove tutti gli elementi con position < 0
        private function spliceTagsTable(offset:int):void {
            if (!decryptedVideoStartsAtTheBeginningOfTheSourceVideo && tagsTable.length > 0) {
                for (var i:int = 0; i < tagsTable.length; i++) {
                    tagsTable[i].tagPosition = tagsTable[i].tagPosition - offset;
                }

                var k:int = getTagsTableFirstValidIndex(); // sono sicuro che la tagsTable non è vuota! (main if)

                tagsTable.splice(0, k); // butta via i primi k elementi

                if (debug && traceTagsTable) {
                    debugTraceTagsTable();
                }
            }
        }


        // se il decryptedVideo è stato troncato allora le prime tagPosition sono negative (e quindi non valide)
        // chi la chiama è sicuro che la tagsTable sia NON vuota...!!!
        private function getTagsTableFirstValidIndex():int {
            var firstValidIndex:int = 0;

            while (tagsTable[firstValidIndex].tagPosition < 0) {
                firstValidIndex++;
            }

            return firstValidIndex;
        }


        // STOP brutale (arresta download e decrypting, ed elimina tutto)
        private function bruteForceStop():void {
            // 1 "chiudo il rubinetto" (in localhost scarico tutto subito, ma vabbè)
            try {
                urlStream.close(); // Immediately closes the stream and cancels the download operation. No data can be read from the stream after the close() method is called.
            } catch (error:Error) {
                sendToTextArea(error.name + error.errorID.toString() + error.message);
            }

            // 2 fermo quello che stavo facendo
            bruteForceStopSignal[0] = true;

            closeAllMessageChannels(); // inutile!!!

            decrypterWorker.terminate();

            // 3 cancello quello che stavo mostrando a video
            netStream.close();
            netStream.dispose(); // Releases all the resources held by the NetStream object
            // The dispose() method is similar to the close method.
            // The main difference between the two methods is that dispose() releases the memory used to display the current video frame.
            // If that frame is currently displayed on screen, the display will go blank. The close() method does not blank the display because it does not release this memory.

            // 4 elimino il video
            decryptedVideo.clear();


            // (5 )resetto la UI
            playingOrPausedVideo = false;
            seekTimeSeconds = 0;
            playTimeSeconds = 0;
            bytesDownloaded = 0;
            bytesDecrypted = 0;
            videoTotalTimeSeconds = 0;
            videoTotalTimeString = getTimeString(0);
            playPauseButton.label = playPauseButtonPlayLabel;
        }


        // dato il tempo trova il keyframe (la sua posizione nel byte array) corrispondente e chiama il seek
        // il seek vero e proprio (avendo la posizione nel byteArray) è chiamato dallo status handler, perché:
        // Capture the "NetStream.Seek.Notify" event to call appendBytesAction() after a seek
        private function seekToTime(playTimeSecond:Number):void {
            if (tagsTable.length > 0 && playTimeSecond < tagsTable[0].tagTime) {
                seekToTime(tagsTable[0].tagTime);
                    // così quando il !decryptedVideoStartsAtTheBeginningOfTheSourceVideo, seeko al primo tag disponibile
                    // also, seekare ad un tempo negativo mi fa seekare a 0
            }

            var nextTagTime:Number = 0;
            var previousTagTime:Number = 0;

            //trace("seeking...");

            // adesso il check sul tempo negativo è superfluo...
            //if (playTimeSecond < 0)
            //{
            //trace("can't seek to a negative time!");
            //return;
            //}
            // non controllo playTimeSecond > videoLength perché videoLength potrei non avercelo (se non ho i metaData)
            // comunque se playTimeSecond > videoLength semplicemente non succede nulla (e va bene così)

            for (var i:int = 1; i < tagsTable.length; i++) {
                nextTagTime = tagsTable[i].tagTime;
                previousTagTime = tagsTable[i - 1].tagTime;

                // prende sempre il precedente, non il più vicino (giusto!)
                if (previousTagTime <= playTimeSecond) {
                    if (playTimeSecond < nextTagTime) {
                        //trace("keyframe found!");
                        //trace("firstValidIndex =", firstValidIndex);
                        seekBytePosition = tagsTable[i - 1].tagPosition; // seekPosition var globale

                        if (seekBytePosition < decryptedVideo.length) // proteggo dal seek ad un punto non ancora decifrato
                        {
                            seekTimeSeconds = previousTagTime;
                            //netStream.seek(seekTime);
                            netStream.seek(0); // notare che il valore passato a seek è totalmente inutile in data generation mode
                                // il passo successivo è in netStatusEventHandler
                        } else {
                            //trace("unable to seek! (not yet decrypted, please wait)");
                        }
                        break;
                    }
                }
            }
        }


        // questa viene chiamata da netStatusEventHandler quando riceve l'evento seek
        private function playVideoAtSeekPosition():void {
            netStream.appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK); // resets the timescale!

            seekedVideo = new ByteArray();

            try {
                //trace("decryptedVideo.length (MB) =", decryptedVideo.length / (1024*1024) );
                //trace("seekPosition (MB) =", seekPosition / (1024*1024) );
                seekedVideo.writeBytes(decryptedVideo, seekBytePosition);
                netStream.appendBytes(seekedVideo);
            } catch (e:MemoryError) {
                if (debug) {
                    trace("MemoryError trying to write seekedVideo");
                    trace(e);
                    trace("FALSE: the system is plenty of memory, but Adobe Flash Player can't handle it!");
                    debugTraceMemoryInfo();
                    debugForceGarbageCollection();
                }

                // ormai il seek l'ho chiamato, devo appendere qualcosa a netstream... il decrypted video!

                if (decryptedVideoStartsAtTheBeginningOfTheSourceVideo) {
                    netStream.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN); // il video riparte dall'inizio!

                    seekTimeSeconds = 0;
                } else // il decryptedVideo è stato troncato
                {
                    //var firstValidIndex:int = getTagsTableFirstValidIndex();

                    //if( firstValidIndex < 0 || !decryptedVideoStartsAtAValidTagPosition )
                    if (tagsTable.length < 1 || !decryptedVideoStartsAtAValidTagPosition) {
                        bruteForceStop();
                            // firstValidIndex < 0 in realtà è impossibile: se la tagsTable è vuota l'ha già verificato seekToTime e altrimenti non sarei qui
                            // !decryptedVideoStartsAtAValidTagPosition : dovrei aver chiamato il seek dopo che il decryptedVideo è esploso ma prima che abbia chiamato shiftLeftDecryptedVideo... quasi impossibile!
                    }

                    //seekTime = tagsTable[firstValidIndex].tagTime;
                    seekTimeSeconds = tagsTable[0].tagTime;
                }

                netStream.appendBytes(decryptedVideo); // in ogni caso, sia che il dV sia troncato o no
            }

            seekedVideo.clear(); // fondamentale per non sprecare memoria


            if (debug) {
                debugTraceTimes();
            }
        }


        /*
         * USER INTERFACE
         */

        private function addedToStageHandler(event:Event):void {
            stage.color = stageColor;

            // Scaling
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            // full screen event
            stage.addEventListener(FullScreenEvent.FULL_SCREEN, stageFullScreenHandler);

            // the StageVideoEvent.STAGE_VIDEO_STATE informs you if StageVideo is available or not
            stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, stageVideoAvailabilityHandler);

            stage.addEventListener(Event.RESIZE, stageResizeHandler);

            initUserInterface();

            // debug purpose
            if (debug) {
                stage.addEventListener(KeyboardEvent.KEY_DOWN, stageKeyDownHandler);
            }
        }


        private function stageFullScreenHandler(event:FullScreenEvent):void {
            switchFullScreenButtonLabel();
        }


        private function stageVideoAvailabilityHandler(event:StageVideoAvailabilityEvent):void {
            if (event.availability == StageVideoAvailability.AVAILABLE)
                stageVideoAvailable = true;
            else
                stageVideoAvailable = false;

            //trace("StageVideo is available:", stageVideoAvailable);

            toggleStageLegacyVideo(stageVideoAvailable); // quando disponibile lo uso!
        }


        private function toggleStageLegacyVideo(useStageVideo:Boolean):void {
            //trace("StageVideo (Direct path) in use:", useStageVideo);

            if (useStageVideo) {
                if (stageVideo == null) // se non l'avevo mai ancora usato
                {
                    //trace("stageVideo era NULL");
                    stageVideo = stage.stageVideos[0];
                    stageVideo.addEventListener(StageVideoEvent.RENDER_STATE, stageVideoRenderStateHandler);
                }

                stageVideo.attachNetStream(netStream);

                if (!stageVideoRunning) // allora stavo usando il legacy Video...! NON la prima volta però!
                {
                    // If we use StageVideo, we just remove from the display list the Video object to avoid covering the StageVideo object (always in the background)
                    if (video != null) // se video non è mai stato usato, non era stato aggiunto allo stage...!
                        stage.removeChild(video);
                }

                stageVideoRunning = true;
            } else // do NOT use stageVideo!
            {
                if (video == null) // se non l'avevo mai ancora usato
                {
                    //trace("video era NULL");
                    video = new Video();
                    video.smoothing = true; // set this property to true to take advantage of mipmapping image optimization
                    video.addEventListener(VideoEvent.RENDER_STATE, videoRenderStateHandler);
                }

                video.attachNetStream(netStream);

                stage.addChildAt(video, 0);

                stageVideoRunning = false;
            }
        }


        private function stageVideoRenderStateHandler(event:StageVideoEvent):void {
            //trace("StageVideoEvent received - Render State:", event.status);
            resize();

            if (debug)
                switchStageVideoButtonLabel();
        }


        private function videoRenderStateHandler(event:VideoEvent):void {
            //trace("VideoEvent received - Render State:", event.status);
            resize();

            if (debug)
                switchStageVideoButtonLabel();
        }


        private function stageResizeHandler(event:Event):void {
            resize();
        }


        private function resize():void {
            if (stageVideoRunning) {
                // set the StageVideo size using the viewPort property
                try {
                    stageVideo.viewPort = getVideoRect(stageVideo.videoWidth, stageVideo.videoHeight);
                } catch (rangeError:RangeError) // One of the parameters is invalid
                {
                    debugSwitchBetweenStageAndLegacyVideo();
                    legacyVideoResize();
                    debugSwitchBetweenStageAndLegacyVideo();
                }
            } else // legacy (classic) Video in Use
            {
                legacyVideoResize();
            }

            resizeUserInterface();
        }


        private function legacyVideoResize():void {
            var videoRectangle:Rectangle = getVideoRect(video.videoWidth, video.videoHeight);

            video.x = videoRectangle.x;
            video.y = videoRectangle.y;
            video.width = videoRectangle.width;
            video.height = videoRectangle.height;
        }


        private function getVideoRect(width:int, height:int):Rectangle {
            var videoWidth:Number = width;
            var videoHeight:Number = height;
            var scaling:Number = Math.min(stage.stageWidth / videoWidth, stage.stageHeight / videoHeight);

            videoWidth *= scaling;
            videoHeight *= scaling;

            var posX:Number = (stage.stageWidth - videoWidth) / 2;
            var posY:Number = (stage.stageHeight - videoHeight) / 2;

            //return new Rectangle(posX, posY, videoWidth, videoHeight);
            // così la barra e i pulsanti non sono sovrapposti al video!
            return new Rectangle(posX, posY, videoWidth, videoHeight - bottomUIpanelHeight);
        }


        private function initUserInterface():void {
            textFormat = new TextFormat(); // lo stesso per tutti!
            textFormat.font = "Kalinga"; // "Kalinga" o "Courier New"
            textFormat.size = 16;

            initButtons();

            initProgressBars();

            initTimer();

            if (debug)
                initTextArea();

            resizeUserInterface();
        }


        private function initButtons():void {
            initFakeTimeButton();

            initPlayPauseButton();

            initStopButton();

            initFakeVolumeButton();

            initVolumeSlider();

            initFullScreenButton();

            if (debug) {
                initBruteForceStopButton();

                initStageVideoButton();
            }
        }


        private function initFakeTimeButton():void {
            bottomButtonsCounter++;

            fakeTimeButton = new Button();

            //timesDisplay.enabled = false; // scritta grigia E non è cliccabile...?!

            fakeTimeButton.label = fakeTimeButtonDefaultLabel;

            fakeTimeButton.height = buttonHeight;

            fakeTimeButton.setStyle("textFormat", textFormat);

            addChild(fakeTimeButton);
        }


        private function initPlayPauseButton():void {
            bottomButtonsCounter++;

            playPauseButton = new Button();

            playPauseButton.label = playPauseButtonPauseLabel;

            playPauseButton.height = buttonHeight;

            playPauseButton.addEventListener(MouseEvent.CLICK, playPauseButtonClickHandler);

            playPauseButton.setStyle("textFormat", textFormat);

            addChild(playPauseButton);
        }


        private function initStopButton():void {
            bottomButtonsCounter++;

            stopButton = new Button();

            stopButton.label = stopButtonLabel;

            stopButton.height = buttonHeight;

            stopButton.addEventListener(MouseEvent.CLICK, stopButtonClickHandler);

            stopButton.setStyle("textFormat", textFormat);

            addChild(stopButton);
        }


        private function initFakeVolumeButton():void {
            fakeVolumeButton = new Button();

            fakeVolumeButton.label = fakeVolumeButtonLabel;

            fakeVolumeButton.height = buttonHeight;

            fakeVolumeButton.setStyle("textFormat", textFormat);

            addChild(fakeVolumeButton);
        }


        private function initVolumeSlider():void {
            bottomButtonsCounter++;

            volumeSlider = new Slider();

            volumeSlider.height = buttonHeight;

            volumeSlider.liveDragging = true;

            volumeSlider.focusEnabled = false;

            volumeSlider.minimum = 0;
            volumeSlider.maximum = 1;
            volumeSlider.snapInterval = 0.01; // volume da 0 a 100
            volumeSlider.value = volumeTransform.volume;
            //volumeSlider.tickInterval = volumeSlider.snapInterval; // così è senza tacche (default is 0)

            volumeSlider.addEventListener(SliderEvent.CHANGE, volumeSliderChangeHandler);

            addChild(volumeSlider);
        }


        private function initFullScreenButton():void {
            bottomButtonsCounter++;

            fullScreenButton = new Button();

            fullScreenButton.label = fullScreenButtonGoFullScreenLabel;

            fullScreenButton.height = buttonHeight;

            fullScreenButton.addEventListener(MouseEvent.CLICK, fullScreenButtonClickHandler);

            fullScreenButton.setStyle("textFormat", textFormat);

            addChild(fullScreenButton);
        }


        private function initBruteForceStopButton():void {
            bruteForceStopButton = new Button();

            bruteForceStopButton.label = bruteForceStopButtonLabel;

            bruteForceStopButton.height = buttonHeight;

            bruteForceStopButton.addEventListener(MouseEvent.CLICK, bruteForceStopButtonClickHandler);

            bruteForceStopButton.setStyle("textFormat", textFormat);

            addChild(bruteForceStopButton);
        }


        private function initStageVideoButton():void {
            stageVideoButton = new Button();

            stageVideoButton.label = stageVideoButtonDefaultLabel;

            stageVideoButton.height = buttonHeight * 2;

            stageVideoButton.addEventListener(MouseEvent.CLICK, stageVideoButtonClickHandler);

            stageVideoButton.setStyle("textFormat", textFormat);

            addChild(stageVideoButton);
        }


        private function initProgressBars():void {
            // ordine fondamentale(sovrapposte)!

            initFakeBackgroundProgressBar();

            initDownloadProgressBar();

            initDecryptingProgressBar();

            initPlayProgressBar();
        }


        private function initFakeBackgroundProgressBar():void {
            fakeBackgroundProgressBar = new ProgressBar();

            fakeBackgroundProgressBar.mode = ProgressBarMode.MANUAL;

            fakeBackgroundProgressBar.indeterminate = false;

            fakeBackgroundProgressBar.minimum = 0;

            fakeBackgroundProgressBar.maximum = 1;

            fakeBackgroundProgressBar.setProgress(1, 1); // sempre piena!

            fakeBackgroundProgressBar.height = progressBarHeight;

            addChild(fakeBackgroundProgressBar);

            fakeBackgroundProgressBar..setStyle("barSkin", ProgressBarSkinRossa);
        }


        private function initDownloadProgressBar():void {
            downloadProgressBar = new ProgressBar();

            downloadProgressBar.mode = ProgressBarMode.MANUAL;

            downloadProgressBar.indeterminate = false;

            downloadProgressBar.minimum = 0;

            downloadProgressBar.maximum = Number.MAX_VALUE; // quando ricevo i metadata assumerà il valore giusto!

            downloadProgressBar.height = progressBarHeight;

            addChild(downloadProgressBar);

            downloadProgressBar.setStyle("barSkin", ProgressBarSkinGialla);
        }


        private function initDecryptingProgressBar():void {
            decryptingProgressBar = new ProgressBar();

            decryptingProgressBar.mode = ProgressBarMode.MANUAL;

            decryptingProgressBar.indeterminate = false;

            decryptingProgressBar.minimum = 0;

            decryptingProgressBar.maximum = Number.MAX_VALUE; // quando ricevo i metadata assumerà il valore giusto!

            decryptingProgressBar.height = progressBarHeight;

            decryptingProgressBar.addEventListener(MouseEvent.CLICK, decryptingProgressBarClickHandler);

            addChild(decryptingProgressBar);

            decryptingProgressBar.setStyle("barSkin", ProgressBarSkinVerde);
        }


        private function initPlayProgressBar():void {
            playProgressBar = new ProgressBar();

            playProgressBar.mode = ProgressBarMode.MANUAL;

            playProgressBar.indeterminate = false;

            playProgressBar.minimum = 0;

            playProgressBar.maximum = Number.MAX_VALUE; // quando ricevo i metadata assumerà il valore giusto!

            playProgressBar.height = progressBarHeight;

            playProgressBar.addEventListener(MouseEvent.CLICK, playProgressBarClickHandler);

            addChild(playProgressBar);

            playProgressBar.setStyle("barSkin", ProgressBarSkinBlu);
        }


        private function initTimer():void {
            timer = new Timer(timerUpdateInterval);

            timer.addEventListener(TimerEvent.TIMER, timerHandler);
        }


        private function timerHandler(event:TimerEvent):void {
            // aggiorno tutte le progressBar (e non solo)
            updatePlayTime();
            updateProgressBars();
            updateFakeTimeButton();
        }


        private function updatePlayTime():void {
            playTimeSeconds = seekTimeSeconds + netStream.time;
        }


        private function updateProgressBars():void {
            downloadProgressBar.setProgress(bytesDownloaded, videoFileTotalSizeBytes);
            decryptingProgressBar.setProgress(bytesDecrypted, videoFileTotalSizeBytes);
            playProgressBar.setProgress(playTimeSeconds, videoTotalTimeSeconds);
        }


        private function updateFakeTimeButton():void {
            var playTimeString:String = getTimeString(playTimeSeconds);

            fakeTimeButton.label = new String(playTimeString + " / " + videoTotalTimeString);
        }


        private function initTextArea():void {
            debugTextArea = new TextArea();

            debugTextArea.editable = false;
            debugTextArea.wordWrap = false;

            debugTextArea.setStyle("textFormat", textFormat);

            addChild(debugTextArea);
        }

        private function sendToTextArea(string:String):void {
            if (debug)
                debugTextArea.text += (string + "\n");
        }


        private function resizeUserInterface():void {
            resizeButtons();

            resizeProgressBars();

            if (debug)
                resizeTextArea();
        }


        private function resizeButtons():void {
            // ordine fondamentale!!!
            buttonWidth = stage.stageWidth / bottomButtonsCounter;

            resizeFakeTimeButton();

            resizePlayPauseButton();

            resizeStopButton();

            resizeFakeVolumeButton();

            resizeVolumeSlider();

            resizeFullScreenButton();

            if (debug) {
                resizeBruteForceStopButton();

                resizeStageVideoButton();
            }
        }


        private function resizeFakeTimeButton():void {
            fakeTimeButton.width = buttonWidth;

            fakeTimeButton.move(0, stage.stageHeight - fakeTimeButton.height);
        }


        private function resizePlayPauseButton():void {
            playPauseButton.width = buttonWidth;

            //playPauseButton.move(0, stage.stageHeight - playPauseButton.height);
            playPauseButton.move(fakeTimeButton.width, stage.stageHeight - playPauseButton.height);
        }


        private function resizeStopButton():void {
            stopButton.width = buttonWidth;

            stopButton.move(fakeTimeButton.width + playPauseButton.width, stage.stageHeight - stopButton.height);
        }


        private function resizeFakeVolumeButton():void {
            fakeVolumeButton.width = buttonWidth;

            fakeVolumeButton.move(fakeTimeButton.width + playPauseButton.width + stopButton.width, stage.stageHeight - fakeVolumeButton.height);
        }


        private function resizeVolumeSlider():void {
            volumeSlider.width = buttonWidth - 2 * (buttonWidth / 20);

            volumeSlider.move(fakeTimeButton.width + playPauseButton.width + stopButton.width + buttonWidth / 20, stage.stageHeight - (volumeSlider.height) * 0.8);
        }


        private function resizeFullScreenButton():void {
            fullScreenButton.width = buttonWidth;

            fullScreenButton.move(fakeTimeButton.width + playPauseButton.width + stopButton.width + buttonWidth, stage.stageHeight - fullScreenButton.height);
        }


        private function resizeBruteForceStopButton():void {
            bruteForceStopButton.width = buttonWidth;

            bruteForceStopButton.move(stage.stageWidth - bruteForceStopButton.width, 0);
        }


        private function resizeStageVideoButton():void {
            stageVideoButton.width = buttonWidth;

            stageVideoButton.move(stage.stageWidth - stageVideoButton.width, bruteForceStopButton.height);
        }


        private function resizeProgressBars():void {
            // ordine fondamentale!!!

            resizeFakeBackgroundProgressBar();

            resizeDownloadProgressBar();

            resizeDecryptingProgressBar();

            resizePlayProgressBar();
        }


        private function resizeFakeBackgroundProgressBar():void {
            fakeBackgroundProgressBar.width = stage.stageWidth;

            fakeBackgroundProgressBar.move(0, stage.stageHeight - buttonHeight - progressBarHeight);
        }


        private function resizeDownloadProgressBar():void {
            downloadProgressBar.width = stage.stageWidth;

            //downloadProgressBar.move(0, stage.stageHeight - playPauseButton.height - playProgressBar.height - decryptingProgressBar.height - downloadProgressBar.height);
            //downloadProgressBar.move(0, stage.stageHeight - playPauseButton.height - playProgressBar.height - downloadProgressBar.height);
            downloadProgressBar.move(0, stage.stageHeight - buttonHeight - progressBarHeight);
        }


        private function resizeDecryptingProgressBar():void {
            decryptingProgressBar.width = stage.stageWidth;

            //decryptingProgressBar.move(0, stage.stageHeight - playPauseButton.height - playProgressBar.height - decryptingProgressBar.height);
            //decryptingProgressBar.move(0, stage.stageHeight - playPauseButton.height - playProgressBar.height - progressBarHeight);
            decryptingProgressBar.move(0, stage.stageHeight - buttonHeight - progressBarHeight);
        }


        private function resizePlayProgressBar():void {
            playProgressBar.width = stage.stageWidth;

            //playProgressBar.move(0, stage.stageHeight - playPauseButton.height - playProgressBar.height);
            playProgressBar.move(0, stage.stageHeight - buttonHeight - progressBarHeight);
        }


        private function resizeTextArea():void {
            debugTextArea.width = stage.stageWidth / 2;

            debugTextArea.height = stage.stageHeight / 2;
        }


        // KEYBOARD AND MOUSE HANDLERS
        private function stageKeyDownHandler(event:KeyboardEvent):void {
            switch (event.keyCode) {
                //case Keyboard.F :
                //toggleFullNormalScreen();
                //break;

                case Keyboard.O:
                    debugSwitchBetweenStageAndLegacyVideo();
                    break;

                //case Keyboard.SPACE : // space preme il pulsante che ha il focus..!
                case Keyboard.P:
                case Keyboard.ENTER:
                    togglePlayPausePlayback();
                    break;

                case Keyboard.S:
                    stopPlayback();
                    break;

                case Keyboard.X:
                    bruteForceStop();
                    break;

                case Keyboard.T:
                    debugTraceTimes();
                    break;

                case Keyboard.N:
                    debugTraceNetStreamInfo();
                    break;

                case Keyboard.M:
                    debugTraceMemoryInfo();
                    break;

                case Keyboard.G:
                    debugForceGarbageCollection();
                    break;

                case Keyboard.K:
                    debugTraceTagsTable();
                    break;

                case Keyboard.LEFT:
                    seekToTime(playTimeSeconds - 10);
                    break;

                case Keyboard.RIGHT:
                    seekToTime(playTimeSeconds + 10);
                    break;

                case Keyboard.UP:
                    seekToTime(playTimeSeconds + 60);
                    break;

                case Keyboard.DOWN:
                    seekToTime(playTimeSeconds - 60);
                    break;

                case Keyboard.NUMBER_0:
                    seekToTime(10);
                    break;

                case Keyboard.NUMBER_1:
                    seekToTime(1 * 60);
                    break;

                case Keyboard.NUMBER_2:
                    seekToTime(2 * 60);
                    break;

                case Keyboard.NUMBER_3:
                    seekToTime(3 * 60);
                    break;

                case Keyboard.NUMBER_4:
                    seekToTime(4 * 60);
                    break;

                case Keyboard.NUMBER_5:
                    seekToTime(5 * 60);
                    break;

                case Keyboard.NUMBER_6:
                    seekToTime(6 * 60);
                    break;

                case Keyboard.NUMBER_7:
                    seekToTime(7 * 60);
                    break;

                case Keyboard.NUMBER_8:
                    seekToTime(8 * 60);
                    break;

                case Keyboard.NUMBER_9:
                    seekToTime(9 * 60);
                    break;

                case Keyboard.Q:
                    seekToTime(55 * 60);
                    break;

                case Keyboard.W:
                    seekToTime(56 * 60);
                    break;

                case Keyboard.E:
                    seekToTime(57 * 60);
                    break;

                case Keyboard.R:
                    seekToTime(58 * 60);
                    break;

                case Keyboard.A:
                    seekToTime(100 * 60);
                    break;
            }
        }


        private function playPauseButtonClickHandler(e:MouseEvent):void {
            togglePlayPausePlayback();
        }


        private function stopButtonClickHandler(e:MouseEvent):void {
            stopPlayback();
        }


        private function volumeSliderChangeHandler(event:SliderEvent):void {
            // Set the volumeTransform's volume property to the current value of the 
            // Slider and set the NetStream object's soundTransform property.
            volumeTransform.volume = event.value;
            netStream.soundTransform = volumeTransform;
        }


        private function fullScreenButtonClickHandler(e:MouseEvent):void {
            toggleFullNormalScreen();
        }


        private function bruteForceStopButtonClickHandler(e:MouseEvent):void {
            bruteForceStop();
        }


        private function stageVideoButtonClickHandler(e:MouseEvent):void {
            debugSwitchBetweenStageAndLegacyVideo();
        }


        private function decryptingProgressBarClickHandler(e:MouseEvent):void {
            seekByClickingOnProgressBar(decryptingProgressBar, e.stageX);
        }


        private function playProgressBarClickHandler(e:MouseEvent):void {
            seekByClickingOnProgressBar(playProgressBar, e.stageX);
        }


        private function seekByClickingOnProgressBar(progressBar:ProgressBar, stageX:Number):void {
            var xCoordInsideProgressBar:Number;

            xCoordInsideProgressBar = stageX - progressBar.x;

            var second:Number;

            // xCoordInsideProgressBar : progressBar.length = second : videoTotalTime
            // => second = ( xCoordInsideProgressBar * videoTotalTime ) / progressBar.width

            if (progressBar.width != 0) // non si sa mai!!!
            {
                second = (xCoordInsideProgressBar * videoTotalTimeSeconds) / progressBar.width;
                seekToTime(second);
            }
        }


        // STOP "grazioso" (il download e il decrypting continuano)
        private function stopPlayback():void {
            if (tagsTable.length > 0 && decryptedVideoStartsAtTheBeginningOfTheSourceVideo) {
                if (playingOrPausedVideo) {
                    pauseAndSeekToTheBeginningOfDecryptedVideo();
                }
            } else {
                bruteForceStop();
            }
        }


        private function pauseAndSeekToTheBeginningOfDecryptedVideo():void {
            if (tagsTable.length > 0) {
                netStream.pause();
                seekToTime(tagsTable[0].tagTime); // così funziona sia che decryptedVideoStartsAtTheBeginningOfTheSourceVideo che no
                playPauseButton.label = playPauseButtonPlayLabel;
            }
        }


        private function togglePlayPausePlayback():void {
            if (playingOrPausedVideo) {
                netStream.togglePause();
            } else {
                startPlayback();
            }

            switchPlayPauseButtonLabel();
        }


        private function switchPlayPauseButtonLabel():void {
            if (playPauseButton.label == playPauseButtonPauseLabel)
                playPauseButton.label = playPauseButtonPlayLabel;
            else
                playPauseButton.label = playPauseButtonPauseLabel;
        }


        private function toggleFullNormalScreen():void {
            if (stage.displayState == StageDisplayState.FULL_SCREEN || stage.displayState == StageDisplayState.FULL_SCREEN_INTERACTIVE) {
                stage.displayState = StageDisplayState.NORMAL;
            } else // allora è normal...
            {
                //stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE; // NO! così in html NON va in full screen!!!
                stage.displayState = StageDisplayState.FULL_SCREEN;
                /*
                 * http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/display/Stage.html#displayState
                 * To enable full-screen interactive mode, which supports keyboard interactivity,
                 * add the allowFullScreenInteractive parameter to the object and embed tags in the HTML page that includes
                 * the SWF file, with allowFullScreenInteractive set to "true", as shown in the following example:
                 *	<param name="allowFullScreenInteractive" value="true" />
                 */
            }
        }


        private function switchFullScreenButtonLabel():void {
            if (stage.displayState == StageDisplayState.FULL_SCREEN || stage.displayState == StageDisplayState.FULL_SCREEN_INTERACTIVE)
                fullScreenButton.label = fullScreenButtonExitFullScreenLabel;
            else
                fullScreenButton.label = fullScreenButtonGoFullScreenLabel;
        }


        private function switchStageVideoButtonLabel():void {
            var stageVideoAvailableLabel:String = new String("StageVideo available: " + stageVideoAvailable);
            var stageVideoRunningLabel:String = new String("StageVideo running: " + stageVideoRunning);

            stageVideoButton.label = new String(stageVideoAvailableLabel + "\n" + stageVideoRunningLabel);
        }


        /*
         * DEBUG FUNCTIONS
         */

        private function debugSwitchBetweenStageAndLegacyVideo():void {
            if (stageVideoAvailable) {
                if (stageVideoRunning)
                    toggleStageLegacyVideo(false);
                else
                    toggleStageLegacyVideo(true);
            }
        }


        private function debugForceGarbageCollection():void {
            System.gc(); // force the garbage collector - For the Flash Player debugger version and AIR applications only.
            trace("garbage collector forced");
        }


        private function debugTraceMemoryInfo():void {
            trace("---------- System Memory Infos ----------");
            trace("System.privateMemory (MB) =", System.privateMemory / (1024 * 1024));
            trace("System.totalMemoryNumber (MB) =", System.totalMemoryNumber / (1024 * 1024));
            trace("System.freeMemory (MB) =", System.freeMemory / (1024 * 1024));
            trace("decryptedVideo size (MB) =", decryptedVideo.length / (1024 * 1024));
            trace("press G to force Garbage Collection");
            trace();
        }


        private function debugTraceNetStreamInfo():void {
            trace("Video File total size (MB) =", videoFileTotalSizeBytes / (1024 * 1024));
            trace("NetStream.bytesLoaded =", netStream.bytesLoaded); // sempre 0...
            trace("NetStream.bytesTotal (MB) =", netStream.bytesTotal / (1024 * 1024)); // sempre 0...
            trace("NetStream.bufferLength (seconds) =", netStream.bufferLength); // The number of seconds of data currently in the buffer
            trace("NetStream.bufferTime (seconds) =", netStream.bufferTime);
            trace("NetStream.bufferTimeMax (seconds) [default 0] =", netStream.bufferTimeMax);
            trace("NetStream.backBufferLength (seconds) [FMS] =", netStream.backBufferLength); // This property is available only when data is streaming from Flash Media Server 3.5.3 or higher
            trace("NetStream.backBufferTime (seconds) [FMS] =", netStream.backBufferTime); // This property is available only when data is streaming from Flash Media Server 3.5.3 or higher
        }


        private function debugUpdateAndTraceTimes():void {
            updatePlayTime();
            debugTraceTimes();
        }


        private function debugTraceTimes() {
            trace();
            trace("NetStream.time =", netStream.time);
            trace("seekTime =", seekTimeSeconds);
            trace("PlayTime =", playTimeSeconds);
        }


        private function debugTraceTagsTable():void {
            trace("tagsTable: start");

            for (var j:int = 0; j < tagsTable.length; j++) {
                trace(tagsTable[j].tagTime + " ; " + tagsTable[j].tagPosition);
            }

            trace("tagsTable: end");
        }


        // così posso costruire la tabella dei tag al volo...?! - NON FUNZIONA / INUTILE!
        //public function onSeekPoint(seekPointObject:Object):void
        //public function onSeekPoint(... args):void
        //{
        ///*
        //* Called synchronously from appendBytes() when the append bytes parser encounters a point that it believes is
        //* a seekable point (for example, a video key frame). Use this event to construct a seek point table.
        //* The byteCount corresponds to the byteCount at the first byte of the parseable message for that seek point,
        //* and is reset to zero as described above.
        //* To seek, at the event NetStream.Seek.Notify, find the bytes that start at a seekable point and call
        //* appendBytes(bytes). If the bytes argument is a ByteArray consisting of bytes starting at the seekable point,
        //* the video plays at that seek point. 
        //* 
        //*/
        //
        //var traceNetStreamInfo:Boolean = false;
        //var traceExtendedArgsInfo:Boolean = false;
        //
        //trace("onSeekPoint entered"); // qui entra.. il motivo era: (... args) FACEPALM!!!
        //
        //if (traceNetStreamInfo)
        //{
        //trace("NetStream.bytesLoaded =", netStream.bytesLoaded); // sempre 0...
        //trace("NetStream.time =", netStream.time);
        //}
        //
        //if (traceExtendedArgsInfo)
        //{
        //for ( var obj:* in args )
        //{
        //trace(obj.toString());
        //
        //for (var i:* in obj)
        //{
        //trace(i + "=" + obj[i]);
        //}
        //
        //var description:XML = describeType(obj);	
        //
        //trace("Properties:");
        //for each (var a:XML in description.accessor) trace(a.@name+" : "+a.@type);
        //
        //trace("Methods:");
        //for each (var m:XML in description.method)
        //{
        //trace(m.@name+" : "+m.@returnType);
        //if (m.parameter != undefined)
        //{
        //trace("     arguments");
        //for each (var p:XML in m.parameter) trace("               - "+p.@type);
        //}
        //}
        //}
        //} // fine if(traceExtendedArgsInfo)
        //}


    } // class closed
} // package closed
