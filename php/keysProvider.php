<?php

// FIXME se un utente LOGGATO scrive a mano "keysprovider.php?axoid=x"...
// vede una pagina bianca se non può vedere il video x
// vede la chiave se può vedere il video x !!!

session_start();

$userID = $_SESSION['userID']; // da verify.php
if ($userID === null) {
    header("Location: login.php?m=2");
    exit();
}

$mySQLconnection = mysqli_connect("localhost:3306", "root", "scp2014", "drmDemo");

// Check connection DEBUG
//if (mysqli_connect_errno())
//    echo "Failed to connect to MySQL: " . mysqli_connect_error();
//else
//    echo "<br>connection to database succesful!<br>";


$axoid = htmlspecialchars($_GET['axoid']);

$axoid = mysqli_real_escape_string($mySQLconnection, $axoid); // protezione da sql injection

// prima devo vedere se l'utente ha il permesso!!!!
$rightQuery = mysqli_query($mySQLconnection, "SELECT * FROM rights WHERE userID = '$userID' AND videoID = '$axoid'");

$right = mysqli_fetch_row($rightQuery);

if ($right[0] === NULL) {
    //header( "Location: login.php?m=1");
    echo ""; //FIXME il player actionscript se riceve una stringa vuota stampa messaggio d'errore?!
    exit();
} else {
    // query per ottenere la chiave dall'axoid...
    $keyQuery = mysqli_query($mySQLconnection, "SELECT * FROM videokeys WHERE axoid = '$axoid'");

    $keyRow = mysqli_fetch_array($keyQuery);

    echo $keyRow[1] . "&" . $keyRow[2] . "&" . $keyRow[3];
}
