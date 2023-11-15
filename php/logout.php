<?php

session_start();

$userID = $_SESSION['userID']; // da verify.php

if ($userID === null)  // se un utente NON loggato scrive a mano /logout.php
{
    header("Location: login.php?m=2");
    exit();
}


// Desetta tutte le variabili di sessione.
session_unset();
// Infine , distrugge la sessione.
session_destroy();

header("Location: login.php?m=3");
exit();
