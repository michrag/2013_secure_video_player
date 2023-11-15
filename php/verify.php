<?php

session_start();

$userID = $_SESSION['userID'];

if ($userID !== null) // se un utente già loggato scrive a mano "verify.php"...
{
    header("Location: welcome.php");
    exit();
}

$mySQLconnection = mysqli_connect("localhost:3306", "root", "scp2014", "drmDemo");
// Check connection
//if (mysqli_connect_errno())
//    echo "Failed to connect to MySQL: " . mysqli_connect_error();
//else
//    echo "connection to database succesful!<br>";

$userName = htmlspecialchars($_POST["name"]); // da login.php
$password = htmlspecialchars(md5($_POST["password"])); // da login.php

if ($userName == null || $password == null) // ==, NON === !!!
{
    header("Location: login.php?m=2");
    exit();
}

$userName = mysqli_real_escape_string($mySQLconnection, $userName); // protezione da sql injection
$password = mysqli_real_escape_string($mySQLconnection, $password);

//FIXME WHERE BINARY name => case sensitive username... Ma NON lo vogliamo! Giusto?!
$userQuery = mysqli_query($mySQLconnection, "SELECT * FROM users WHERE name = '$userName' AND password = '$password'");

$user = mysqli_fetch_array($userQuery);

if ($user[id] === NULL) {
    header("Location: login.php?m=1");
    exit();
} else {
    $_SESSION['userID'] = $user[id];
    $_SESSION['username'] = $user[name];

    header("Location: welcome.php");
    exit();
}
