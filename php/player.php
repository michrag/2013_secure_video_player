<?php

session_start();

$userID = $_SESSION['userID']; // da verify.php

if ($userID === null) {
	header("Location: login.php?m=2");
	exit();
}

$keysProviderURL = $_SESSION['$keysProviderURL']; // registrata da welcome.php

$mySQLconnection = mysqli_connect("localhost:3306", "root", "scp2014", "drmDemo");

$axoid = htmlspecialchars($_GET['axoid']);

$axoid = mysqli_real_escape_string($mySQLconnection, $axoid); // protezione da sql injection

$keysProviderURL = "$keysProviderURL" . "?axoid=" . $axoid;

// query per ottenere l'url del video richiesto
$videoURLquery = mysqli_query($mySQLconnection, "SELECT url FROM videourls WHERE axoid = '$axoid'");

$row = mysqli_fetch_array($videoURLquery);

$videoURL = $row[url];
?>
<html>

<head>
	<meta charset="UTF-8">
	<title>Player</title>
	<style type="text/css" media="screen">
		html,
		body {
			height: 100%;
			background-color: #ffffff;
		}

		body {
			margin: 0;
			padding: 0;
			overflow: hidden;
		}

		#flashContent {
			width: 100%;
			height: 100%;
		}
	</style>

	<script language="JavaScript">
		// onunload e non onunbeforeunload perché con la seconda, tornando indietro col pulsante back del mio mouse,
		// il plugin si blocca...!!!
		window.onunload = function(evt) {
			var flashObject = document.getElementById("Player");

			try {
				// "fromJavaScript" è il nome che in actionscript è associato alla funzione da chiamare
				// in pratica, se modifico tale nome qui lo devo modificare anche in AS3 e viceversa!!!
				flashObject.fromJavaScript(true); // se NON ha argomenti NON ci vanno le parentesi!
			} catch (e) {
				alert(e);
				return e;
			}

			//con onbeforeunload ("deprecated") (!!!) se lo abilito, chiede conferma.
			//return "do you really want to quit?"; // alcuni browser comunque ignorano questa stringa
		}
	</script>


</head>

<body>
	<div id="flashContent">
		<!--This is a comment. Comments are not displayed in the browser-->
		<object type="application/x-shockwave-flash" data="Player.swf" width="100%" height="100%" id="Player" style="float: none; vertical-align:middle">
			<param name="movie" value="Player.swf" />

			<!--se vengono modificate le flashVars qui, devono essere modificate coerentemente anche nell'actionscript!!!-->
			<param name="flashVars" value="videoURL=<?php print "$videoURL"; ?>&keysProviderURL=<?php print "$keysProviderURL"; ?>" />

			<param name="quality" value="high" />
			<param name="bgcolor" value="#ffffff" />
			<param name="play" value="true" />
			<param name="loop" value="false" />
			<param name="wmode" value="direct" />
			<param name="scale" value="showall" />
			<param name="menu" value="false" />
			<param name="devicefont" value="false" />
			<param name="salign" value="" />
			<param name="allowScriptAccess" value="always" />
			<param name="allowFullScreen" value="true" />
			<a href="http://www.adobe.com/go/getflash">
				<img src="http://www.adobe.com/images/shared/download_buttons/get_flash_player.gif" alt="Get Adobe Flash player" />
			</a>
		</object>
	</div>
</body>

</html>