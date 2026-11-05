package com.storemanager.core.data

open class DatabaseException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

class DatabaseInitializationException(message: String, cause: Throwable? = null) : DatabaseException(message, cause)

class DatabaseValidationException(message: String, cause: Throwable? = null) : DatabaseException(message, cause)
